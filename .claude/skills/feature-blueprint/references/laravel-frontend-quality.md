# View, test, verification, security, performance and rollout templates

Continues the Invoicing worked example from `laravel-backend.md`. Same rules: complete files, paths first, no comments.

Contents: 07-View · 08-Jobs_Events · 09-Test · 10-Security · 11-Performance · 12-Verify · 13-Rollout

Each section is the content of one layer file. Inside the real file, split it into tasks in the format from `layer-catalog.md` (header, full code, acceptance criteria, Verify command).

---

## 07-View

Match the project's layout component and form components (check `resources/views/components`); the names below are placeholders for them. States to cover in every list and form page: empty, validation error, success flash, and loading when Alpine is involved. Keyboard and screen-reader notes go in the package text: every input has a visible label, errors are tied to inputs with `aria-describedby`, the destructive action asks for confirmation.

`resources/views/invoices/index.blade.php`

```blade
<x-layouts.app title="Invoices">
    <div class="flex items-center justify-between">
        <h1 class="text-2xl font-semibold">Invoices</h1>
        <a href="{{ route('invoices.create') }}" class="rounded bg-indigo-600 px-4 py-2 text-white">New invoice</a>
    </div>

    @if (session('status'))
        <p role="status" class="mt-4 rounded bg-green-50 p-3 text-green-800">{{ session('status') }}</p>
    @endif

    @if ($invoices->isEmpty())
        <p class="mt-8 text-gray-600">No invoices yet. Create your first one.</p>
    @else
        <table class="mt-6 w-full text-left">
            <caption class="sr-only">Your invoices</caption>
            <thead>
                <tr>
                    <th scope="col" class="py-2">Number</th>
                    <th scope="col" class="py-2">Status</th>
                    <th scope="col" class="py-2 text-right">Total</th>
                    <th scope="col" class="py-2">Due</th>
                </tr>
            </thead>
            <tbody>
                @foreach ($invoices as $invoice)
                    <tr class="border-t">
                        <td class="py-2"><a href="{{ route('invoices.show', $invoice) }}" class="underline">{{ $invoice->number }}</a></td>
                        <td class="py-2">{{ $invoice->status->label() }}</td>
                        <td class="py-2 text-right">{{ $invoice->totalFormatted() }}</td>
                        <td class="py-2">{{ $invoice->due_at?->toFormattedDateString() }}</td>
                    </tr>
                @endforeach
            </tbody>
        </table>

        <div class="mt-6">{{ $invoices->links() }}</div>
    @endif
</x-layouts.app>
```

`resources/views/invoices/create.blade.php`

```blade
<x-layouts.app title="New invoice">
    <h1 class="text-2xl font-semibold">New invoice</h1>

    <form method="POST" action="{{ route('invoices.store') }}" class="mt-6 max-w-md space-y-4" novalidate>
        @csrf

        <div>
            <label for="currency" class="block font-medium">Currency</label>
            <input id="currency" name="currency" value="{{ old('currency', 'USD') }}" maxlength="3"
                   aria-describedby="currency-error" class="mt-1 w-full rounded border p-2 uppercase">
            @error('currency')
                <p id="currency-error" class="mt-1 text-sm text-red-700">{{ $message }}</p>
            @enderror
        </div>

        <div>
            <label for="total" class="block font-medium">Total</label>
            <input id="total" name="total" type="number" step="0.01" min="0.01" value="{{ old('total') }}"
                   aria-describedby="total-error" class="mt-1 w-full rounded border p-2">
            @error('total')
                <p id="total-error" class="mt-1 text-sm text-red-700">{{ $message }}</p>
            @enderror
        </div>

        <div>
            <label for="due_at" class="block font-medium">Due date</label>
            <input id="due_at" name="due_at" type="date" value="{{ old('due_at') }}"
                   aria-describedby="due_at-error" class="mt-1 w-full rounded border p-2">
            @error('due_at')
                <p id="due_at-error" class="mt-1 text-sm text-red-700">{{ $message }}</p>
            @enderror
        </div>

        <button type="submit" class="rounded bg-indigo-600 px-4 py-2 text-white">Create invoice</button>
    </form>
</x-layouts.app>
```

`resources/views/invoices/show.blade.php`

```blade
<x-layouts.app :title="$invoice->number">
    <h1 class="text-2xl font-semibold">{{ $invoice->number }}</h1>

    @if (session('status'))
        <p role="status" class="mt-4 rounded bg-green-50 p-3 text-green-800">{{ session('status') }}</p>
    @endif

    @error('status')
        <p role="alert" class="mt-4 rounded bg-red-50 p-3 text-red-800">{{ $message }}</p>
    @enderror

    <dl class="mt-6 grid max-w-md grid-cols-2 gap-2">
        <dt class="font-medium">Status</dt>
        <dd>{{ $invoice->status->label() }}</dd>
        <dt class="font-medium">Total</dt>
        <dd>{{ $invoice->totalFormatted() }}</dd>
        <dt class="font-medium">Due</dt>
        <dd>{{ $invoice->due_at?->toFormattedDateString() }}</dd>
    </dl>

    <div class="mt-6 flex gap-3">
        @can('markPaid', $invoice)
            <form method="POST" action="{{ route('invoices.pay', $invoice) }}">
                @csrf
                <button type="submit" class="rounded bg-green-700 px-4 py-2 text-white">Mark as paid</button>
            </form>
        @endcan

        @can('delete', $invoice)
            <form method="POST" action="{{ route('invoices.destroy', $invoice) }}" x-data
                  x-on:submit="if (! confirm('Delete this draft invoice?')) $event.preventDefault()">
                @csrf
                @method('DELETE')
                <button type="submit" class="rounded border border-red-700 px-4 py-2 text-red-700">Delete</button>
            </form>
        @endcan
    </div>
</x-layouts.app>
```

Apply: `npm run build`, open `/invoices` as a normal user. Definition of done includes: tab through each form with the keyboard only, resize to 360px wide, check the empty state.

---

## 09-Test

Open the package with the traceability matrix, one row per BRD acceptance criterion:

| Criterion | Test file | Test name |
|---|---|---|
| AC-1 owner creates an invoice | `tests/Feature/InvoiceTest.php` | `an owner can create an invoice` |
| AC-2 another user cannot view it | same | `another user cannot view an invoice` |
| AC-3 invalid input saves nothing | same | `invalid input is rejected and nothing is saved` |

`tests/Feature/InvoiceTest.php` (Pest)

```php
<?php

declare(strict_types=1);

use App\Enums\InvoiceStatus;
use App\Models\Invoice;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;

uses(RefreshDatabase::class);

it('redirects guests to login', function (): void {
    $this->get(route('invoices.index'))->assertRedirect(route('login'));
});

it('lists only the invoices of the signed-in user', function (): void {
    $user = User::factory()->create();
    $mine = Invoice::factory()->for($user)->create();
    $theirs = Invoice::factory()->create();

    $this->actingAs($user)
        ->get(route('invoices.index'))
        ->assertOk()
        ->assertSee($mine->number)
        ->assertDontSee($theirs->number);
});

it('shows the empty state when there are no invoices', function (): void {
    $this->actingAs(User::factory()->create())
        ->get(route('invoices.index'))
        ->assertOk()
        ->assertSee('No invoices yet');
});

it('an owner can create an invoice', function (): void {
    $user = User::factory()->create();

    $this->actingAs($user)
        ->post(route('invoices.store'), [
            'currency' => 'USD',
            'total' => '125.50',
            'due_at' => now()->addWeek()->toDateString(),
        ])
        ->assertRedirect();

    $invoice = Invoice::sole();
    expect($invoice->user_id)->toBe($user->id)
        ->and($invoice->total_cents)->toBe(12550)
        ->and($invoice->status)->toBe(InvoiceStatus::Draft)
        ->and($invoice->number)->toStartWith('INV-');
});

it('invalid input is rejected and nothing is saved', function (array $payload, string $field): void {
    $this->actingAs(User::factory()->create())
        ->post(route('invoices.store'), $payload)
        ->assertSessionHasErrors($field);

    expect(Invoice::count())->toBe(0);
})->with([
    'missing total' => [['currency' => 'USD', 'due_at' => '2999-01-01'], 'total'],
    'bad currency' => [['currency' => 'US', 'total' => '10', 'due_at' => '2999-01-01'], 'currency'],
    'past due date' => [['currency' => 'USD', 'total' => '10', 'due_at' => '2000-01-01'], 'due_at'],
]);

it('another user cannot view an invoice', function (): void {
    $invoice = Invoice::factory()->create();

    $this->actingAs(User::factory()->create())
        ->get(route('invoices.show', $invoice))
        ->assertForbidden();
});

it('ignores status and user_id smuggled into the request', function (): void {
    $user = User::factory()->create();
    $other = User::factory()->create();

    $this->actingAs($user)->post(route('invoices.store'), [
        'currency' => 'USD',
        'total' => '10',
        'due_at' => now()->addWeek()->toDateString(),
        'status' => 'paid',
        'user_id' => $other->id,
    ]);

    $invoice = Invoice::sole();
    expect($invoice->user_id)->toBe($user->id)
        ->and($invoice->status)->toBe(InvoiceStatus::Draft);
});

it('only an admin can mark a sent invoice as paid', function (): void {
    $invoice = Invoice::factory()->sent()->create();

    $this->actingAs($invoice->user)->post(route('invoices.pay', $invoice))->assertForbidden();

    $admin = User::factory()->create(['is_admin' => true]);
    $this->actingAs($admin)->post(route('invoices.pay', $invoice))->assertRedirect();

    expect($invoice->fresh()->status)->toBe(InvoiceStatus::Paid);
});

it('refuses to delete an invoice that is no longer a draft', function (): void {
    $invoice = Invoice::factory()->sent()->create();

    $this->actingAs($invoice->user)
        ->delete(route('invoices.destroy', $invoice))
        ->assertForbidden();
});

it('loads the invoice list in a constant number of queries', function (): void {
    $user = User::factory()->create();
    Invoice::factory()->count(30)->for($user)->create();

    DB::enableQueryLog();
    $this->actingAs($user)->get(route('invoices.index'))->assertOk();

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(5);
});
```

`tests/Unit/InvoiceStatusTest.php`

```php
<?php

declare(strict_types=1);

use App\Enums\InvoiceStatus;

it('allows only the documented transitions', function (InvoiceStatus $from, InvoiceStatus $to, bool $allowed): void {
    expect($from->canTransitionTo($to))->toBe($allowed);
})->with([
    [InvoiceStatus::Draft, InvoiceStatus::Sent, true],
    [InvoiceStatus::Draft, InvoiceStatus::Paid, false],
    [InvoiceStatus::Sent, InvoiceStatus::Paid, true],
    [InvoiceStatus::Paid, InvoiceStatus::Void, false],
    [InvoiceStatus::Void, InvoiceStatus::Sent, false],
]);
```

Apply: `php artisan test --filter=Invoice`. Expected: all green, no skipped. Replace the traceability matrix with the real test names after writing the tests.

---

## 12-Verify

A reviewer who did not write the code works through this package. Every line has an expected result, so a tick means something.

```markdown
## Automated
| Command | Expected |
|---|---|
| `php artisan migrate:fresh --seed` | completes, no errors |
| `php artisan test` | all pass |
| `vendor/bin/pint --test` | no changes needed |
| `vendor/bin/phpstan analyse` | no errors at the project's level |
| `npm run build` | completes |
| `php artisan route:list --path=invoices` | six routes, all `auth` + `verified` |

## Schema audit
- [ ] `php artisan db:table invoices` matches the contract: columns, types, nullability
- [ ] Indexes exist: `user_id,status`, `status,due_at`, unique `number`
- [ ] Rolling back one step and migrating again leaves the same schema

## Behaviour walkthrough (browser, as a normal user)
1. Sign in, open `/invoices` — empty state shown.
2. Create an invoice with valid data — redirected to its page, flash shown, number `INV-<year>-000001`.
3. Submit the form empty — three field errors, nothing saved, entered values kept.
4. Open another user's invoice URL — 403, not 404 and not the page.
5. Delete the draft — gone from the list; row soft-deleted in the table.
6. As admin, mark a sent invoice as paid — status changes, `InvoicePaid` queued.

## Code audit
- [ ] Every controller action authorises via policy or FormRequest
- [ ] No `$request->all()`, no raw SQL with interpolation
- [ ] `status` and `user_id` absent from `$fillable`
- [ ] No lazy loading in views: tests pass with `Model::preventLazyLoading()` on
- [ ] No unused imports; no comments; strict types in every file
- [ ] Every BRD acceptance criterion maps to a passing test (traceability table complete)

## Accessibility audit
- [ ] Every input has a label, errors announced, focus order follows the visual order
- [ ] Contrast of status and error text meets AA
- [ ] Works at 360px and at 200% zoom

## Logs
- [ ] `storage/logs/laravel.log` has no new errors after the walkthrough
```

---

## 10-Security

Threat table first, then the controls with the code that implements them. Controls already in another package are referenced, not repeated.

| Threat | Example | Control | Where | Proof |
|---|---|---|---|---|
| Broken access control | User A opens user B's invoice by id | Policy `view` | `InvoicePolicy`, `Gate::authorize` | `another user cannot view an invoice` |
| Privilege escalation | Normal user marks an invoice paid | Policy `markPaid` admin-only | `InvoicePolicy` | `only an admin can mark a sent invoice as paid` |
| Mass assignment | Posting `status=paid` or `user_id` | Not in `$fillable`, DTO mapping | `Invoice`, `StoreInvoiceRequest` | `ignores status and user_id smuggled into the request` |
| Injection | Sort or filter parameter reaches SQL | Bound values, whitelisted sort columns | `Invoice` scopes | review item |
| XSS | Free text rendered in a page | `{{ }}` only, never `{!! !!}` on user input | views | review item |
| CSRF | Cross-site form post | `@csrf`, `VerifyCsrfToken` on web group | views | feature test on `pay` |
| Abuse | Repeated pay or create calls | `throttle` middleware | routes | below |
| Enumeration | Guessing sequential ids | Authorisation on every read, 403 not data | policy | covered |
| Audit gap | No trail of who paid what | Observer or activity log entry | `InvoiceObserver` | below |

Rate-limit test, `tests/Feature/InvoiceThrottleTest.php`:

```php
<?php

declare(strict_types=1);

use App\Models\Invoice;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;

uses(RefreshDatabase::class);

it('throttles repeated pay attempts', function (): void {
    $admin = User::factory()->create(['is_admin' => true]);
    $invoice = Invoice::factory()->sent()->create();

    foreach (range(1, 31) as $attempt) {
        $response = $this->actingAs($admin)->post(route('invoices.pay', $invoice));
    }

    $response->assertStatus(429);
});
```

Audit log entry on payment, added to `app/Listeners/RecordInvoicePayment.php`:

```php
<?php

declare(strict_types=1);

namespace App\Listeners;

use App\Events\InvoicePaid;
use Illuminate\Support\Facades\Log;

class RecordInvoicePayment
{
    public function handle(InvoicePaid $event): void
    {
        Log::channel('audit')->info('invoice.paid', [
            'invoice_id' => $event->invoice->id,
            'user_id' => $event->invoice->user_id,
            'total_cents' => $event->invoice->total_cents,
        ]);
    }
}
```

Close the package with: dependency audit (`composer audit`, `npm audit --omit=dev`), secrets check (nothing in the repo, `.env.example` has keys only), and personal data inventory with retention.

---

## 11-Performance

State the volume and the targets before the code, so "fast enough" is a number.

| Item | Assumption or target |
|---|---|
| Rows in `invoices` at 12 months | 2,000,000 |
| Invoices per user (p99) | 5,000 |
| List page | p95 under 150 ms, at most 5 queries |
| Detail page | p95 under 100 ms, at most 3 queries |
| Memory per request | under 32 MB |

Seeder, `database/seeders/InvoiceBenchSeeder.php`:

```php
<?php

declare(strict_types=1);

namespace Database\Seeders;

use App\Models\Invoice;
use App\Models\User;
use Illuminate\Database\Seeder;

class InvoiceBenchSeeder extends Seeder
{
    public function run(): void
    {
        $users = User::factory()->count(400)->create();

        $users->each(function (User $user): void {
            foreach (range(1, 50) as $batch) {
                Invoice::factory()->count(100)->for($user)->sent()->create();
            }
        });
    }
}
```

Query plan check. Run on the seeded database and expect an index range scan, not a full scan:

```sql
EXPLAIN SELECT * FROM invoices
WHERE user_id = 1 AND deleted_at IS NULL
ORDER BY id DESC LIMIT 20;
```

Expected: `key` is `invoices_user_id_status_index` or the primary key, rows examined near 20 to a few hundred, no `Using filesort` on a large set. If the plan scans, add or change the index in `01-Migration` and say so.

Regression test, `tests/Feature/InvoicePerformanceTest.php`:

```php
<?php

declare(strict_types=1);

use App\Models\Invoice;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;

uses(RefreshDatabase::class);

it('keeps the list page within its query and time budget', function (): void {
    $user = User::factory()->create();
    Invoice::factory()->count(200)->for($user)->sent()->create();

    DB::enableQueryLog();
    $started = hrtime(true);

    $this->actingAs($user)->get(route('invoices.index'))->assertOk();

    $milliseconds = (hrtime(true) - $started) / 1_000_000;

    expect(count(DB::getQueryLog()))->toBeLessThanOrEqual(5)
        ->and($milliseconds)->toBeLessThan(500);
});
```

Load script with k6, `tests/bench/invoices.js`:

```js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
    vus: 20,
    duration: '60s',
    thresholds: {
        http_req_duration: ['p(95)<150'],
        http_req_failed: ['rate<0.01'],
    },
};

export default function () {
    const response = http.get(`${__ENV.BASE_URL}/invoices`, {
        headers: { Cookie: __ENV.SESSION_COOKIE },
    });
    check(response, { 'status is 200': (r) => r.status === 200 });
    sleep(1);
}
```

Apply: `php artisan db:seed --class=InvoiceBenchSeeder` on a throwaway database, then `k6 run -e BASE_URL=http://localhost:8000 -e SESSION_COOKIE="..." tests/bench/invoices.js`. Record the measured numbers in the package so the next change has a baseline. When a target is missed: first read the query log, then the plan, then consider caching with a named invalidation, last consider denormalisation.

---

## 13-Rollout

```markdown
## Order
1. Merge migration; deploy with `php artisan migrate --force`.
2. Deploy application code behind the flag `invoicing`.
3. `php artisan queue:restart` after every deploy that changes a job or listener.
4. Enable the flag for staff, then 10% of users, then everyone.

## Feature flag
Config key `features.invoicing`, read through one helper; routes return 404 when off.

## Monitoring
| Signal | Alert when |
|---|---|
| 5xx on `/invoices*` | above 1% for 5 minutes |
| Failed jobs in `InvoicePaid` listeners | any |
| p95 of `/invoices` | above 300 ms for 10 minutes |

## Rollback
Turn the flag off. The migration is additive; do not roll it back with data in it. If a rollback of schema is unavoidable, the exact command and the data loss it causes.

## First-week runbook
Who watches the dashboards, where the audit log is, how to void an invoice by hand.
```

---

## 08-Jobs_Events

`app/Events/InvoicePaid.php`

```php
<?php

declare(strict_types=1);

namespace App\Events;

use App\Models\Invoice;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class InvoicePaid
{
    use Dispatchable;
    use SerializesModels;

    public function __construct(public readonly Invoice $invoice) {}
}
```

`app/Jobs/SendInvoiceReceipt.php`

```php
<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Models\Invoice;
use App\Notifications\InvoiceReceipt;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;

class SendInvoiceReceipt implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;

    public int $timeout = 30;

    public function __construct(public readonly Invoice $invoice) {}

    public function backoff(): array
    {
        return [10, 60, 300];
    }

    public function handle(): void
    {
        if ($this->invoice->receipt_sent_at !== null) {
            return;
        }

        $this->invoice->user->notify(new InvoiceReceipt($this->invoice));
        $this->invoice->forceFill(['receipt_sent_at' => now()])->save();
    }
}
```

`receipt_sent_at` is in the Migration package and the contract, as every column a job touches must be; the idempotency check above is what makes a retry safe. Test with `Queue::fake()` for dispatch and a direct `handle()` call twice for idempotency.
