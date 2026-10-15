# Laravel 13: what changed, and what the model gets wrong

> **Verified** against the official docs on 2026-10-15: the [13.x upgrade guide](https://laravel.com/docs/13.x/upgrade), [Controllers](https://laravel.com/docs/13.x/controllers), [Cache](https://laravel.com/docs/13.x/cache), [Eloquent: Mutators & Casting](https://laravel.com/docs/13.x/eloquent-mutators) and [Image Manipulation](https://laravel.com/docs/13.x/images). The rules below come from those pages.
> **When Laravel Boost is installed, its `search-docs` tool is the version-matched source.** If it disagrees with this file, follow Boost and tell the user this file is stale.

Read this when the session report says Laravel 13. Everything in the slim-skeleton table in `SKILL.md` still applies (no `Http/Kernel.php`, no `Console/Kernel.php`, no `Exceptions/Handler.php`, providers in `bootstrap/providers.php`).

## High impact

| Laravel 12 | Laravel 13 |
|---|---|
| CSRF middleware `VerifyCsrfToken` / `ValidateCsrfToken` | Renamed to `Illuminate\Foundation\Http\Middleware\PreventRequestForgery`, which also checks the `Sec-Fetch-Site` header. The old names remain as **deprecated aliases**. Reference the new class, e.g. `->withoutMiddleware([PreventRequestForgery::class])` in tests. The middleware config API has `preventRequestForgery(...)`. |
| Dependencies | `laravel/framework ^13.0`; `phpunit/phpunit ^12.0`; `pestphp/pest ^4.0`; `laravel/boost ^2.0`; `laravel/tinker ^3.0`. |

## Medium impact: these break quietly

- **`cache.serializable_classes` is `false` in the new default config.** It hardens cache unserialization against gadget chains. PHP objects (Eloquent models, collections, DTOs) put in the cache **won't come back as objects**. Cache arrays (`->toArray()`, `->pluck()`), or list the exact classes in `config/cache.php` → `'serializable_classes' => [...]`. The session report says whether this project has the setting.
- **`upsert()` with an empty `uniqueBy`** now throws `InvalidArgumentException` instead of generating bad SQL. Always pass the unique column(s).

## Low impact, but the model will write the old form

- New skeletons default the session to `serialization => json`. Don't store PHP objects in the session. Switching an existing app from `php` to `json` logs everyone out.
- Default cache, Redis and session-cookie prefixes are hyphenated (`app-cache-`). This only matters if the app relies on framework fallbacks; set `CACHE_PREFIX` / `REDIS_PREFIX` / `SESSION_COOKIE` to keep the old keys.
- `JobAttempted::$exceptionOccurred` → `$exception`; `QueueBusy::$connection` → `$connectionName`.
- Bootstrap 3 pagination view names: `pagination::bootstrap-3`, `pagination::simple-bootstrap-3`.
- MySQL `DELETE … JOIN` now keeps `ORDER BY`/`LIMIT`. MySQL and MariaDB before 11.8.1 may now throw instead of running an unbounded delete.
- Routes with an explicit domain match before non-domain routes.
- `Js::from` no longer escapes Unicode. `array_first()`/`array_last()` come from a PHP 8.5 polyfill, so use `Arr::first()`/`Arr::last()`.

## Available in 13.x: prefer these to hand-rolled versions

- **Controller middleware as attributes:** `#[Middleware('auth')]`, `#[Middleware('log', only: ['index'])]`, `#[WithoutMiddleware(...)]`, and `#[Authorize('update', 'post')]` on a method (a shortcut for the `can` middleware). `implements HasMiddleware` + `public static function middleware(): array` still works. `$this->middleware()` in a constructor does **not**.
- **Casts:** the docs define casts with `protected function casts(): array`. Use that form in new code. Existing `protected $casts` arrays still work, so don't churn them in an unrelated task.
- **Cache:** `Cache::flexible($key, [$fresh, $stale], fn)` (stale-while-revalidate), `Cache::memo()` (per-request memoization), `Cache::touch($key, $ttl)`, `Cache::withoutOverlapping()` and `Cache::funnel()` (concurrency limits), and the `failover` cache driver.
- **Images (core):** `$request->image('avatar')->cover(400, 400)->toWebp()->storePublicly('avatars', 's3')`. Needs `intervention/image:^4.0` and GD or Imagick; see `files-and-images.md`.

## Laravel Boost (first-party MCP server)

Boost (`composer require laravel/boost --dev`, then `php artisan boost:install`) gives the agent version-matched tools. The names below are from Boost v2.10.3's own `tools/list`:

| Tool | Use it for | Writes? |
|---|---|---|
| `search-docs` | Version-specific docs for the installed packages. Use it before relying on memory. | no |
| `database-schema` | Tables, columns, indexes. Cheaper than reading every migration. | no |
| `database-query` | Read-only SQL, e.g. to check what a feature actually stored. | no |
| `application-info` | PHP/Laravel/package versions, models. | no |
| `last-error` / `read-log-entries` | The real exception when a test or request fails. | no |
| `browser-logs` | Frontend errors, useful for `[browser]` criteria. | no |
| `get-absolute-url` | Correct URLs for routes. | no |
| `record-rule` | Writes a durable, committed project rule to `.ai/rules`. | **yes** |

In Claude Code they're called `mcp__laravel-boost__<tool>`.
