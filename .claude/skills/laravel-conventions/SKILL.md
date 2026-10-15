---
name: laravel-conventions
description: Laravel 11/12/13 conventions — the slim skeleton, routing and controllers, FormRequests, Eloquent and query performance, authorization, caching, queues, and the mistakes that only surface in production. Load before writing or reviewing anything under app/, routes/, database/ or config/.
---

# Laravel conventions

Assume the **slim skeleton (Laravel 11+)** unless the session-start stack report says otherwise. **On Laravel 13, read `references/laravel13.md` first.** When Laravel Boost is installed, its `search-docs` tool is the version-matched source and overrides this skill on API details. The stack report is authoritative — check it before assuming Livewire, Pest, Pint, a permission package, or a cache driver exists.

## What changed in the slim skeleton, and why it matters

The model's training data is full of Laravel 8/9 code that no longer works. In 11+:

| Gone | Now |
|---|---|
| `app/Http/Kernel.php` | `bootstrap/app.php` → `->withMiddleware(fn (Middleware $m) => ...)` |
| `app/Console/Kernel.php` | `routes/console.php` for the schedule; commands in `app/Console/Commands` autoregister |
| `app/Exceptions/Handler.php` | `bootstrap/app.php` → `->withExceptions(...)` |
| `RouteServiceProvider` | `bootstrap/app.php` → `->withRouting(...)`; extra route files go in its `then:` closure |
| provider registration in `config/app.php` | `bootstrap/providers.php` |
| `$this->middleware()` in a controller constructor | route-level middleware, or `implements HasMiddleware` + `public static function middleware(): array` |
| `protected $casts = []` | `protected function casts(): array` is the documented form for new code (the property still works, so don't churn existing models) |

Never create one of the dead files. If one already exists in the repo, check `bootstrap/providers.php` before assuming it runs.

## The layering everything else follows from

**A request flows: route → middleware → FormRequest → controller → service/action → model → response.** Each layer does one thing:

- **Routes** name and group. No logic, no queries in closures — a closure route cannot be `route:cache`d.
- **Middleware** answers "may this request proceed at all".
- **FormRequest** holds the validation rules *and* the authorization for that one action. `authorize()` returning a bare `true` means the route middleware is carrying the whole check — make sure it actually is.
- **Controller** translates request to response: resolve input, call one thing, return a redirect/view/response. If a method is more than ~30 lines it is doing someone else's job.
- **Service / action class** holds the operation and owns the transaction boundary. This is where "create the order, charge the card, send the mail" lives.
- **Model** holds relationships, casts, scopes and accessors. Not business processes.
- **Observers / events** handle the *incidental* consequences of a write — cache invalidation, audit rows. Never the core operation, because they fire on mass updates you did not expect and not at all on `Model::query()->update()`.

## Non-negotiables

1. **`env()` only in `config/`.** Everywhere else it returns `null` the moment `php artisan config:cache` runs — which every production deploy does. Add a key to a config file and read `config('services.thing.key')`.
2. **Never mass-assign the raw request.** `$request->validated()`, or `$request->only([...])`. `$request->all()` writes whatever the client sent, bounded only by `$fillable`.
3. **Never interpolate into raw SQL.** `whereRaw('col = ?', [$v])`, never `whereRaw("col = $v")`. Column names and sort directions cannot be bound — whitelist them.
4. **Every list query is paginated and eager-loaded.** `->with(...)` for what the view touches, `->paginate()` for anything unbounded. A view that calls `$model->relation` inside a loop is N+1.
5. **Writes that touch more than one table run in `DB::transaction()`.**
6. **Nothing slow happens in the request.** Mail, image processing, external HTTP → a queued job.
7. **Use the framework's own tools before adding a package.** Policies before a permission package; `Cache::remember` before a caching library; a form request before a validation helper.

## References

Read the one that matches the task — don't read all of them:

- `references/http-layer.md` — routing, controllers, FormRequests, middleware, responses, route model binding, API endpoints.
- `references/eloquent-and-data.md` — models, relationships, N+1, migrations, transactions, large datasets.
- `references/auth-and-authorization.md` — gates, policies, where the check belongs, and hand-rolled RBAC.
- `references/laravel13.md` — **Laravel 13**: what changed (CSRF → `PreventRequestForgery`, `cache.serializable_classes`, upsert), what's new (controller middleware attributes, `Cache::flexible`/`memo`, core image API), and the Laravel Boost MCP tools. Verified against laravel.com.
- `references/caching-and-queues.md` — cache keys and invalidation, tags, jobs, the scheduler, config/route caching.
- `references/redis-and-cache.md` — Redis client and connections, tags, locks, `flexible`, rate-limiter store, pipelines, what never to do on a shared Redis. Verified.
- `references/files-and-images.md` — upload validation, public vs private storage, S3, CDN URLs and caching, image processing and variants, direct-to-S3 uploads. Verified.
- `references/security.md` — rate limiting, passwords and sessions, encryption, signed URLs, SSRF and path traversal, production config, supply chain.
- `references/testing.md` — Pest/PHPUnit, feature tests, factories, database strategy, what is worth testing.
- `references/pitfalls.md` — the failures that appear only in production or only under load. Check this before declaring a task done.

## Related

- `blade-conventions` — what may live in a `.blade.php` file, components, forms, Alpine, and styling. Load it alongside this one for anything with a view.
- `php-conventions` — naming, types, functions, exceptions, for every file regardless of layer.

## Verification

A Laravel change is not done until the test suite passes, and is not trustworthy until you have exercised the actual route. Use the exact commands from the session-start stack report. `php artisan route:list --path=<segment>` is the cheapest way to confirm a route is registered the way you think it is.
