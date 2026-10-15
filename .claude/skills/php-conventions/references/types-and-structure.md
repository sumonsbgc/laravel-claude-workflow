# Types, classes and structure

## Value objects and DTOs

When a method takes five related scalars, they are one thing:

```php
final readonly class EditionKey
{
    public function __construct(public Carbon $date, public int $pageNo) {}

    public function cacheKey(): string { return "edition:{$this->date->toDateString()}:{$this->pageNo}"; }
}
```

- `final readonly` unless you have a reason not to. Immutable data cannot be corrupted at a distance.
- Behaviour that belongs to the data belongs on the object — `cacheKey()` here, so the key is defined once.
- A DTO built from a request is `::fromRequest(StoreNewsRequest $r): self` — one place where validated input becomes a typed object.

## Enums over constants

```php
enum NewsStatus: int
{
    case Published = 1;
    case Draft = 2;

    public function label(): string
    {
        return match ($this) { self::Published => 'Published', self::Draft => 'Draft' };
    }
}
```

Cast it on the model (`'news_status' => NewsStatus::class`) and the magic numbers disappear from controllers, views and tests at once. Adding a case then makes every exhaustive `match` fail loudly instead of falling through.

## Dependency injection

- Constructor-promote dependencies: `public function __construct(private readonly CacheService $cache) {}`.
- Type-hint the interface when there is a real second implementation; the concrete class otherwise. An interface with one implementation is indirection, not abstraction.
- Never `new` a service that has dependencies of its own — let the container build it.
- No service location in the body (`app(Thing::class)`, `resolve()`) except in a factory or a provider. It hides what a class needs and makes it untestable.
- Bind in a service provider when construction is non-trivial:
  ```php
  $this->app->singleton(OptionService::class, fn ($app) => new OptionService($app['cache.store']));
  ```
  `singleton` shares one instance per request — never hold per-user state in one.

## Static and global

- Static methods for pure functions and named constructors (`::fromRequest`). Not for anything with state.
- Facades are fine in Laravel code; in a class that has a constructor already, inject instead — it is testable without `Facade::fake()`.
- Global state (a static array, a singleton holding request data) survives between queued jobs and Octane requests. That is a cross-request data leak.

## Arrays

- Keys are constants or enum values when they are part of a contract; string literals repeated in four files are a bug waiting for a typo.
- `array_map`/`array_filter` for small pure transforms; a Collection when the chain is longer.
- Spread and named arguments over `array_merge` for options.
- Document the shape when a returned array is structured: `@return array{items: News[], total: int}`.

## Static analysis

If the stack report names PHPStan/Larastan, its baseline is a contract — never add to the baseline to silence a new error, and never `@phpstan-ignore` without a comment saying why. If the project has no static analysis, the type hints above are what stands in for it, so leaving them off is not a neutral choice.
