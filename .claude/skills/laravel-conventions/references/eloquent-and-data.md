# Eloquent and the data layer

## Models hold shape, not process

A model declares its table's shape and its relationships. It does not orchestrate a business operation.

```php
class News extends Model
{
    protected $fillable = ['title', 'body', 'page_no', 'category_id', 'published_at'];

    protected function casts(): array          // Laravel 11+: a method, not $casts
    {
        return [
            'published_at' => 'datetime',
            'meta'         => 'array',
            'is_active'    => 'boolean',
        ];
    }

    public function category(): BelongsTo { return $this->belongsTo(Category::class); }

    public function scopePublished(Builder $q): void { $q->where('is_active', 1)->whereNotNull('published_at'); }
}
```

- **Always declare `$fillable`.** `$guarded = []` disables mass-assignment protection entirely.
- **Cast everything that isn't a string.** Without a cast, `is_active` is `"0"` — truthy — and every `if ($news->is_active)` is wrong.
- **Scopes for reusable filters**, so `News::published()` is one thing that cannot drift between call sites.
- Accessors are computed per instance: never query inside one. An accessor with a query fires once per row in a list.
- `$appends` sends a computed attribute to JSON on every serialization, including inside queued jobs. Add it deliberately.

## N+1 — the default failure mode

```php
// 1 + N queries: one per row
$news = News::latest()->paginate(20);
foreach ($news as $item) { echo $item->category->name; }

// 2 queries
$news = News::with('category')->latest()->paginate(20);

// counts without loading the rows
$news = News::withCount('comments')->get();      // $item->comments_count
```

- `with()` for what the view reads, `withCount()` for counts, `loadMissing()` when the collection already exists.
- Constrain what you load: `with(['comments' => fn ($q) => $q->latest()->limit(3)])`.
- **Turn lazy loading into an exception in development** — this is the single highest-value line you can add to `AppServiceProvider::boot()`:
  ```php
  Model::preventLazyLoading(! app()->isProduction());
  ```
- `select()` the columns you need on wide tables, but always include the foreign keys the relations need or the relation silently returns null.

## Queries

- `Model::query()->...` to start a chain; it reads better and types better than a bare static.
- `->exists()` instead of `->count() > 0`, `->doesntExist()` instead of `! ->count()`.
- `->firstOrFail()` / `findOrFail()` for "must exist" — they produce a 404, not a null-property fatal.
- `whereBelongsTo($user)` over `where('user_id', $user->id)`.
- Never pass user input as a column or a direction. Whitelist first:
  ```php
  $sort = in_array($request->sort, ['title', 'created_at'], true) ? $request->sort : 'created_at';
  $dir  = $request->dir === 'asc' ? 'asc' : 'desc';
  ```
- `paginate()` for pages, `simplePaginate()` when a total count is expensive, `cursorPaginate()` for infinite scroll over large tables.

## Large datasets

- `chunkById(500, ...)` for a backfill — plain `chunk()` skips rows when the loop mutates the same column it orders by.
- `lazy()` / `cursor()` to stream without loading the whole result into memory.
- Bulk writes go through `upsert()` or a single `insert()`, not a loop of `create()`. Neither fires model events — if an observer maintains a cache or a derived column, invalidate it explicitly afterwards.

## Transactions

```php
DB::transaction(function () use ($data) {
    $order = Order::create($data);
    $order->items()->createMany($data['items']);
    $this->stock->reserve($order);
});
```

- Anything that writes to more than one table is one transaction.
- Nothing external inside the transaction — no HTTP call, no mail, no queue dispatch that expects the row to be visible. Dispatch **after** commit (`DB::afterCommit()` or dispatch outside the closure); a job can otherwise start before the transaction commits and not find the row.
- Second argument is a retry count for deadlocks: `DB::transaction(fn () => ..., 3)`.

## Migrations

```php
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('news', function (Blueprint $table) {
            $table->id();
            $table->foreignId('category_id')->constrained()->cascadeOnDelete();
            $table->string('title');
            $table->unsignedSmallInteger('page_no')->index();
            $table->timestamp('published_at')->nullable();
            $table->timestamps();

            $table->index(['page_no', 'published_at']);
        });
    }

    public function down(): void { Schema::dropIfExists('news'); }
};
```

- **Index every column you filter, join or sort by.** Adding an index later to a populated table is a maintenance window.
- `foreignId()->constrained()` with an explicit `cascadeOnDelete()` / `nullOnDelete()` — a `foreignId()` alone is just an integer column.
- Always write `down()`. If a migration is genuinely irreversible, say so in a comment.
- One migration per change, never edited after it has run anywhere but your machine.
- Data changes belong in a migration only if they are small and idempotent; anything larger is a command you can re-run and observe.
- Check the SQL before running it against real data: `php artisan migrate --pretend`.

## Factories and seeders

- Every model that appears in a test gets a factory. States (`->published()`, `->draft()`) express the cases the tests need.
- Seeders are for development fixtures and genuinely required reference rows (roles, permissions, settings) — and must be idempotent, so use `firstOrCreate`/`upsert`, never bare `create()`.
