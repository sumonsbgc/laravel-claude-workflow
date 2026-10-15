# Caching, queues and the scheduler

## The rule that makes caching safe

**Every cache write needs a named owner of its invalidation.** Before you add `Cache::remember`, answer: what event makes this value wrong, and what code deletes it when that happens? If there is no answer, you are shipping a bug that appears hours later and cannot be reproduced.

```php
// read
$pages = Cache::remember("news_pages_{$date}", now()->addDay(), fn () => $this->loadPages($date));

// the owner of the invalidation — an observer on the model that makes it stale
class NewsObserver
{
    public function saved(News $news): void   { $this->flush($news); }
    public function deleted(News $news): void { $this->flush($news); }

    private function flush(News $news): void
    {
        Cache::forget("news_pages_{$news->date}");
    }
}
```

- Keys are built from a helper, never typed twice. A key written as `"news_pages_{$date}"` in one file and `"news_page_{$date}"` in another is a cache that never clears.
- `Model::query()->update()` and `insert()` **do not fire model events**, so an observer-based invalidation silently misses them. Invalidate explicitly after a bulk write.
- `Cache::tags(['news'])->flush()` is only available on redis/memcached — check the driver in the stack report before relying on tags, and keep a key-list fallback if the app runs on `file` or `database` anywhere.
- `Cache::flexible($key, [300, 3600], $fn)` (Laravel 11.23+) serves the stale value and refreshes in the background — the right tool for an expensive read on a hot page.
- `Cache::lock('import', 60)->get(fn () => ...)` around anything that must not run twice concurrently.
- Never cache per-user data under a key that isn't per-user. That is how one user's page ends up served to another.

## Queues

Anything that talks to the network, processes an image, or takes longer than a page render belongs in a job.

```php
class ImportEdition implements ShouldQueue
{
    use Queueable;

    public int $tries = 3;
    public int $timeout = 300;
    public array $backoff = [10, 60, 300];

    public function __construct(public News $news) {}   // SerializesModels re-fetches by id

    public function handle(ImageService $images): void { ... }
}
```

- A job holding a model is serialized **by id** and re-fetched on execution: unsaved changes are lost, and a deleted row makes the job fail. Pass ids and load explicitly when that matters.
- Set `$tries`, `$timeout` and `$backoff` on every job. A job with no timeout can wedge a worker indefinitely.
- Jobs must be idempotent — a retry will happen. Guard with a status column or `ShouldBeUnique`.
- Dispatch **after** the transaction commits, or the worker may pick the job up before the row exists.
- `dispatchAfterResponse()` for short work that should not delay the response but does not deserve a worker.
- Failed jobs land in `failed_jobs`; a job with no `failed()` method and nobody watching that table is a silent data loss.
- Changing job code requires `queue:restart` — workers hold the old class in memory. Say so in your report when a change needs it.

## The scheduler

In `routes/console.php` (Laravel 11+):

```php
Schedule::command('epaper:import')->hourly()->withoutOverlapping()->onOneServer();
```

- `withoutOverlapping()` on anything that can outlive its interval.
- `onOneServer()` when more than one host runs the scheduler.
- Test the command directly (`php artisan epaper:import --dry-run`) — the schedule itself is configuration.

## Config, route and view caching

Production runs `config:cache`, `route:cache`, `view:cache` (usually via `php artisan optimize`). Three consequences you must design around:

1. **`env()` returns null outside `config/`.** This is the single most common "works locally, broken in production" bug in Laravel.
2. **Closure routes break `route:cache`.** Use controller actions.
3. **Config values are frozen at deploy.** Anything that must change at runtime belongs in the database (a settings table read through a cached service), not in config.

After changing `config/`, run `php artisan config:clear` locally or the old cached values keep being served.
