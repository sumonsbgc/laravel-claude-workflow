# Backend package templates

Worked example: an **Invoicing** feature. Adapt names, columns and patterns to the contract and the project; the shape of each package is what matters. Every block is complete and comment-free, as the packages must be.

Contents: Migration · Enum · Trait · Model · Observer · Policy · Factory · DTO and Service · Repository (optional) · Form Request · Controller · Routes · API Resource

---

## 02-Migration

Package body: a column rationale table (why this type, why nullable), an index rationale table (which query each index serves), FK delete behaviour, then the file.

`database/migrations/2026_01_10_000000_create_invoices_table.php`

```php
<?php

declare(strict_types=1);

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('invoices', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('number', 32)->unique();
            $table->string('status', 16)->default('draft');
            $table->char('currency', 3);
            $table->unsignedBigInteger('total_cents');
            $table->timestamp('issued_at')->nullable();
            $table->timestamp('due_at')->nullable();
            $table->timestamp('paid_at')->nullable();
            $table->timestamp('receipt_sent_at')->nullable();
            $table->softDeletes();
            $table->timestamps();

            $table->index(['user_id', 'status']);
            $table->index(['status', 'due_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('invoices');
    }
};
```

When altering a populated table, add the backfill and say whether the change locks the table: a nullable column with no default is cheap, an index on a large table is a maintenance step, a type change is a rewrite.

Apply: `php artisan migrate --pretend`, then `php artisan migrate`, then `php artisan migrate:rollback --step=1` and migrate again to prove `down()`.

---

## 03-Model

### Enum

`app/Enums/InvoiceStatus.php`

```php
<?php

declare(strict_types=1);

namespace App\Enums;

enum InvoiceStatus: string
{
    case Draft = 'draft';
    case Sent = 'sent';
    case Paid = 'paid';
    case Void = 'void';

    public function label(): string
    {
        return match ($this) {
            self::Draft => 'Draft',
            self::Sent => 'Sent',
            self::Paid => 'Paid',
            self::Void => 'Void',
        };
    }

    public function canTransitionTo(self $next): bool
    {
        return match ($this) {
            self::Draft => in_array($next, [self::Sent, self::Void], true),
            self::Sent => in_array($next, [self::Paid, self::Void], true),
            self::Paid, self::Void => false,
        };
    }
}
```

### Trait

`app/Models/Concerns/HasReferenceNumber.php`

```php
<?php

declare(strict_types=1);

namespace App\Models\Concerns;

use Illuminate\Database\Eloquent\Model;

trait HasReferenceNumber
{
    public static function bootHasReferenceNumber(): void
    {
        static::creating(function (Model $model): void {
            if ($model->number === null) {
                $model->number = static::nextReferenceNumber();
            }
        });
    }

    protected static function nextReferenceNumber(): string
    {
        $prefix = 'INV-'.now()->format('Y').'-';
        $last = static::withTrashed()
            ->where('number', 'like', $prefix.'%')
            ->max('number');

        $sequence = $last === null ? 1 : ((int) substr($last, -6)) + 1;

        return $prefix.str_pad((string) $sequence, 6, '0', STR_PAD_LEFT);
    }
}
```

Note in the package: the sequence is computed inside the creating transaction; concurrent creates rely on the unique index and a retry in the service. Name the retry.

### Model

`app/Models/Invoice.php`

```php
<?php

declare(strict_types=1);

namespace App\Models;

use App\Enums\InvoiceStatus;
use App\Models\Concerns\HasReferenceNumber;
use App\Observers\InvoiceObserver;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

#[ObservedBy(InvoiceObserver::class)]
class Invoice extends Model
{
    use HasFactory;
    use HasReferenceNumber;
    use SoftDeletes;

    protected $fillable = [
        'user_id',
        'currency',
        'total_cents',
        'due_at',
    ];

    protected function casts(): array
    {
        return [
            'status' => InvoiceStatus::class,
            'total_cents' => 'integer',
            'issued_at' => 'datetime',
            'due_at' => 'datetime',
            'paid_at' => 'datetime',
        ];
    }

    /**
     * @return BelongsTo<User, $this>
     */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function scopeOwnedBy(Builder $query, User $user): Builder
    {
        return $query->where('user_id', $user->id);
    }

    public function scopeOverdue(Builder $query): Builder
    {
        return $query
            ->where('status', InvoiceStatus::Sent)
            ->where('due_at', '<', now());
    }

    public function totalFormatted(): string
    {
        return number_format($this->total_cents / 100, 2).' '.$this->currency;
    }
}
```

### Observer

`app/Observers/InvoiceObserver.php`

```php
<?php

declare(strict_types=1);

namespace App\Observers;

use App\Enums\InvoiceStatus;
use App\Events\InvoicePaid;
use App\Models\Invoice;
use Illuminate\Support\Facades\Cache;

class InvoiceObserver
{
    public function saved(Invoice $invoice): void
    {
        Cache::forget("users.{$invoice->user_id}.invoice-totals");
    }

    public function updated(Invoice $invoice): void
    {
        if ($invoice->wasChanged('status') && $invoice->status === InvoiceStatus::Paid) {
            InvoicePaid::dispatch($invoice);
        }
    }

    public function deleted(Invoice $invoice): void
    {
        Cache::forget("users.{$invoice->user_id}.invoice-totals");
    }
}
```

Note in the package: `Invoice::query()->update()` and bulk inserts fire no model events, so cache invalidation here misses them. Say which code paths must use model saves.

### Policy

`app/Policies/InvoicePolicy.php`

```php
<?php

declare(strict_types=1);

namespace App\Policies;

use App\Enums\InvoiceStatus;
use App\Models\Invoice;
use App\Models\User;

class InvoicePolicy
{
    public function viewAny(User $user): bool
    {
        return true;
    }

    public function view(User $user, Invoice $invoice): bool
    {
        return $user->is_admin || $invoice->user_id === $user->id;
    }

    public function create(User $user): bool
    {
        return true;
    }

    public function markPaid(User $user, Invoice $invoice): bool
    {
        return $user->is_admin && $invoice->status === InvoiceStatus::Sent;
    }

    public function delete(User $user, Invoice $invoice): bool
    {
        return $invoice->user_id === $user->id && $invoice->status === InvoiceStatus::Draft;
    }
}
```

Policies are auto-discovered when named `<Model>Policy` in `app/Policies`; say so in the package so nobody registers it twice.

### Factory

`database/factories/InvoiceFactory.php`

```php
<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Enums\InvoiceStatus;
use App\Models\Invoice;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Invoice>
 */
class InvoiceFactory extends Factory
{
    protected $model = Invoice::class;

    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'currency' => 'USD',
            'total_cents' => fake()->numberBetween(1_000, 500_000),
            'due_at' => now()->addDays(30),
        ];
    }

    public function sent(): static
    {
        return $this->state(fn (): array => [
            'status' => InvoiceStatus::Sent,
            'issued_at' => now(),
        ]);
    }

    public function paid(): static
    {
        return $this->state(fn (): array => [
            'status' => InvoiceStatus::Paid,
            'issued_at' => now()->subDays(10),
            'paid_at' => now(),
        ]);
    }

    public function overdue(): static
    {
        return $this->sent()->state(fn (): array => [
            'due_at' => now()->subDays(5),
        ]);
    }
}
```

Apply: `php artisan tinker --execute="Invoice::factory()->sent()->create()"` on a local database; `php artisan test --filter=InvoiceModelTest`.

---

## 04-Service (action or service pattern)

`app/Data/CreateInvoiceData.php`

```php
<?php

declare(strict_types=1);

namespace App\Data;

use Carbon\CarbonImmutable;

final readonly class CreateInvoiceData
{
    public function __construct(
        public int $userId,
        public string $currency,
        public int $totalCents,
        public CarbonImmutable $dueAt,
    ) {}
}
```

`app/Services/InvoiceService.php`

```php
<?php

declare(strict_types=1);

namespace App\Services;

use App\Data\CreateInvoiceData;
use App\Enums\InvoiceStatus;
use App\Exceptions\InvalidInvoiceTransition;
use App\Models\Invoice;
use Illuminate\Support\Facades\DB;

class InvoiceService
{
    public function create(CreateInvoiceData $data): Invoice
    {
        return DB::transaction(function () use ($data): Invoice {
            return Invoice::create([
                'user_id' => $data->userId,
                'currency' => $data->currency,
                'total_cents' => $data->totalCents,
                'due_at' => $data->dueAt,
            ]);
        }, attempts: 3);
    }

    public function send(Invoice $invoice): Invoice
    {
        return $this->transition($invoice, InvoiceStatus::Sent, ['issued_at' => now()]);
    }

    public function markPaid(Invoice $invoice): Invoice
    {
        return $this->transition($invoice, InvoiceStatus::Paid, ['paid_at' => now()]);
    }

    private function transition(Invoice $invoice, InvoiceStatus $next, array $attributes): Invoice
    {
        if (! $invoice->status->canTransitionTo($next)) {
            throw InvalidInvoiceTransition::between($invoice->status, $next);
        }

        $invoice->forceFill([...$attributes, 'status' => $next])->save();

        return $invoice;
    }
}
```

`app/Exceptions/InvalidInvoiceTransition.php`

```php
<?php

declare(strict_types=1);

namespace App\Exceptions;

use App\Enums\InvoiceStatus;
use DomainException;

class InvalidInvoiceTransition extends DomainException
{
    public static function between(InvoiceStatus $from, InvoiceStatus $to): self
    {
        return new self("An invoice cannot move from {$from->value} to {$to->value}.");
    }
}
```

The `attempts: 3` transaction retry covers the unique-number race from the trait: a duplicate `number` raises a deadlock-class or unique violation and the transaction runs again with a fresh sequence. State this in the package. Every import in a delivered file must be used.

---

## 04-Service as a repository (only when the project already uses repositories)

Say why: swap persistence, or the project already follows the pattern. Otherwise the service above is enough, because an Eloquent model already is a repository.

`app/Repositories/Contracts/InvoiceRepository.php`

```php
<?php

declare(strict_types=1);

namespace App\Repositories\Contracts;

use App\Models\Invoice;
use App\Models\User;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

interface InvoiceRepository
{
    public function paginateFor(User $user, int $perPage = 20): LengthAwarePaginator;

    public function find(int $id): ?Invoice;

    public function store(array $attributes): Invoice;
}
```

`app/Repositories/EloquentInvoiceRepository.php`

```php
<?php

declare(strict_types=1);

namespace App\Repositories;

use App\Models\Invoice;
use App\Models\User;
use App\Repositories\Contracts\InvoiceRepository;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;

class EloquentInvoiceRepository implements InvoiceRepository
{
    public function paginateFor(User $user, int $perPage = 20): LengthAwarePaginator
    {
        return Invoice::query()
            ->ownedBy($user)
            ->latest('id')
            ->paginate($perPage);
    }

    public function find(int $id): ?Invoice
    {
        return Invoice::find($id);
    }

    public function store(array $attributes): Invoice
    {
        return Invoice::create($attributes);
    }
}
```

Binding in `app/Providers/AppServiceProvider.php`:

```php
public function register(): void
{
    $this->app->bind(InvoiceRepository::class, EloquentInvoiceRepository::class);
}
```

---

## 06-Controller

### Form Request

`app/Http/Requests/StoreInvoiceRequest.php`

```php
<?php

declare(strict_types=1);

namespace App\Http\Requests;

use App\Data\CreateInvoiceData;
use App\Models\Invoice;
use Carbon\CarbonImmutable;
use Illuminate\Foundation\Http\FormRequest;

class StoreInvoiceRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Invoice::class);
    }

    public function rules(): array
    {
        return [
            'currency' => ['required', 'string', 'size:3', 'uppercase'],
            'total' => ['required', 'numeric', 'min:0.01', 'max:1000000'],
            'due_at' => ['required', 'date', 'after:today'],
        ];
    }

    public function toData(): CreateInvoiceData
    {
        return new CreateInvoiceData(
            userId: $this->user()->id,
            currency: $this->validated('currency'),
            totalCents: (int) round($this->validated('total') * 100),
            dueAt: CarbonImmutable::parse($this->validated('due_at')),
        );
    }
}
```

### Controller

`app/Http/Controllers/InvoiceController.php`

```php
<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Exceptions\InvalidInvoiceTransition;
use App\Http\Requests\StoreInvoiceRequest;
use App\Models\Invoice;
use App\Services\InvoiceService;
use Illuminate\Contracts\View\View;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class InvoiceController extends Controller
{
    public function __construct(private readonly InvoiceService $invoices) {}

    public function index(Request $request): View
    {
        Gate::authorize('viewAny', Invoice::class);

        return view('invoices.index', [
            'invoices' => Invoice::query()
                ->ownedBy($request->user())
                ->latest('id')
                ->paginate(20),
        ]);
    }

    public function create(): View
    {
        Gate::authorize('create', Invoice::class);

        return view('invoices.create');
    }

    public function store(StoreInvoiceRequest $request): RedirectResponse
    {
        $invoice = $this->invoices->create($request->toData());

        return to_route('invoices.show', $invoice)->with('status', 'Invoice created.');
    }

    public function show(Invoice $invoice): View
    {
        Gate::authorize('view', $invoice);

        return view('invoices.show', ['invoice' => $invoice]);
    }

    public function pay(Invoice $invoice): RedirectResponse
    {
        Gate::authorize('markPaid', $invoice);

        try {
            $this->invoices->markPaid($invoice);
        } catch (InvalidInvoiceTransition $exception) {
            return back()->withErrors(['status' => $exception->getMessage()]);
        }

        return back()->with('status', 'Invoice marked as paid.');
    }

    public function destroy(Invoice $invoice): RedirectResponse
    {
        Gate::authorize('delete', $invoice);

        $invoice->delete();

        return to_route('invoices.index')->with('status', 'Invoice deleted.');
    }
}
```

Admins who must see every invoice need their own screen or a scope decision in the contract; the index above is deliberately owner-scoped. Say which in the package.

### Routes

`routes/web.php`

```php
Route::middleware(['auth', 'verified'])->group(function (): void {
    Route::resource('invoices', InvoiceController::class)
        ->only(['index', 'create', 'store', 'show', 'destroy']);
    Route::post('invoices/{invoice}/pay', [InvoiceController::class, 'pay'])
        ->middleware('throttle:30,1')
        ->name('invoices.pay');
});
```

Apply: `php artisan route:list --path=invoices`, expected: six rows, all under `auth` and `verified`.

---

### API Resource (part of 06-Controller, only when there is an API)

`app/Http/Resources/InvoiceResource.php`

```php
<?php

declare(strict_types=1);

namespace App\Http\Resources;

use App\Models\Invoice;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Invoice
 */
class InvoiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'number' => $this->number,
            'status' => $this->status->value,
            'currency' => $this->currency,
            'total_cents' => $this->total_cents,
            'issued_at' => $this->issued_at?->toIso8601String(),
            'due_at' => $this->due_at?->toIso8601String(),
            'paid_at' => $this->paid_at?->toIso8601String(),
        ];
    }
}
```
