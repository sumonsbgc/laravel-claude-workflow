# Pitfalls — the ones that only show up in production

Check this list before declaring a task done.

**`env()` outside `config/`** — returns `null` after `config:cache`. The feature works on your machine and is dead on the server. Always `config('...')`.

**Closure routes** — `route:cache` fails outright, so a single closure route disables route caching everywhere.

**`$request->all()` into a write** — every extra field the client sends is a column write, bounded only by `$fillable`. `is_admin`, `status`, `price` all travel that way.

**Missing per-object authorization** — the route middleware proves the user has a role; it does not prove this row is theirs. Change the id in the URL and check what happens.

**N+1** — invisible locally with 5 rows, fatal with 5,000. `Model::preventLazyLoading(! app()->isProduction())` in `AppServiceProvider::boot()` turns it into an exception during development.

**Mass updates skip model events** — `Model::query()->update([...])`, `insert()`, `upsert()` and `delete()` on a builder fire no observers, so caches are not busted and audit rows are not written.

**Dispatching a job inside a transaction** — the worker can start before the commit and not find the row. Dispatch after commit.

**A queued job holding an unsaved model** — `SerializesModels` re-fetches by id; anything you set but did not save is gone by the time it runs.

**Queue workers hold old code** — after changing a job class, `queue:restart` is required. Same for `config:clear` after touching `config/`.

**Timezones** — the database stores UTC, `config('app.timezone')` governs display. Comparing a raw column against a local-time string is off by hours. Cast to `datetime` and compare Carbon instances.

**Booleans without a cast** — `"0"` from the database is truthy. Cast every boolean column.

**`whereRaw`/`orderByRaw` with interpolation** — SQL injection. Bindings for values; a whitelist for column names and directions.

**File uploads without `mimes:` and `max:`** — an unbounded upload is a disk-full outage and a stored-XSS vector.

**`storage:link` missing on the server** — every uploaded image 404s in production and nowhere else.

**Soft deletes and unique indexes** — a soft-deleted row still occupies its unique key, so recreating the "same" record fails. Scope the unique index or hard-delete.

**Eager loading a relation that was already loaded** — `with()` after `get()` does nothing; use `load()` on the collection.

**Blade `{{ }}` inside `<script>`** — HTML escaping, not JavaScript escaping. Use `@js()`.

**Interpolated Tailwind class names** — `bg-{{ $color }}-500` is never generated because the scanner reads source text.

**Sessions and cache sharing a driver on multiple servers** — a `file` driver on two hosts means a user is logged out every other request.

**`config:cache` with a closure in a config file** — the config cannot be serialized and the whole app 500s at boot.

**`optimize` after every deploy** — if the deploy does not also run `migrate`, the app serves cached routes for controllers whose columns do not exist yet.
