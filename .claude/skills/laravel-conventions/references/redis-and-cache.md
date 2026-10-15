# Redis and caching

> **Verified** against [Cache](https://laravel.com/docs/13.x/cache), [Redis](https://laravel.com/docs/13.x/redis) and [Rate Limiting](https://laravel.com/docs/13.x/rate-limiting) (13.x, 2026-10-15). Lines marked *(practice)* are general Redis engineering advice, not quotes from the Laravel docs.

Read the session report first: it names the cache store and Redis client actually in use. Match them, and don't switch drivers inside a feature task.

## Client and connections

- **phpredis is the default and the recommended client** (`'client' => env('REDIS_CLIENT', 'phpredis')`, and the docs say "we encourage you to install and use the PhpRedis PHP extension"). `predis/predis` is the pure-PHP fallback. If the project uses predis (`REDIS_CLIENT=predis`), keep it.
- The default `config/database.php` has **two Redis connections**: `default` (`REDIS_DB`, 0) and `cache` (`REDIS_CACHE_DB`, 1). The cache store uses `connection => 'cache'` and `lock_connection => 'default'`. Keep cache data off the queue/session database, so a `Cache::flush()` can't take queued jobs with it.
- TLS: `'scheme' => 'tls'` on the connection. Retries: phpredis supports `max_retries`, `backoff_algorithm` (`decorrelated_jitter`, …), `backoff_base`, `backoff_cap`. Laravel retries safe reads once by default, and `command_retries` covers the rest.
- Serialization and compression (phpredis only): `options.serializer` (`Redis::SERIALIZER_IGBINARY` / `_MSGPACK`) and `options.compression` (`Redis::COMPRESSION_LZ4` / `_ZSTD`). Only change these on a fresh keyspace *(practice)*: existing keys were written in the old format.
- Native Redis cluster is the default (`options.cluster = 'redis'`) and handles failover.

## Using the cache well

```php
// Read-through with an explicit TTL, plus a tag you can invalidate.
$ads = Cache::tags(['ads'])->remember("ads:active:{$position}", now()->plus(minutes: 10),
    fn () => Advertisement::active()->where('position', $position)->get()->toArray());   // array, not models (L13: serializable_classes)

// Hot page, expensive query: serve stale and refresh after the response.
$stats = Cache::flexible('dashboard:stats', [300, 3600], fn () => $this->stats->compute());

// Invalidate on write: an observer or the service that does the write, never a TTL "eventually".
Cache::tags(['ads'])->flush();
```

- **Tags** are supported on Redis and Memcached, and **not** on `file`, `dynamodb`, `database` or `storage` (the docs say so explicitly). If the store is database/file, use explicit keys plus `Cache::forget()`.
- **Every cached value needs a named invalidation**: an observer, a tag flush in the writing service, or `Cache::forget()`. The kit's PHP guard warns when a cache write has none.
- **Laravel 13:** `cache.serializable_classes = false` means models and collections don't survive the cache. Cache `->toArray()` / `->pluck()` results, or allow-list the class.
- `Cache::flush()` "does not respect your configured cache prefix and will remove all entries from the cache". Never call it from application code on a shared Redis.
- **Atomic locks** (`Cache::lock('key', 10)->block(5, fn)`) for "only one at a time" work; `Cache::withoutOverlapping()` and `Cache::funnel()->limit(3)` for concurrency caps. Locks need a store that supports them (redis, memcached, dynamodb, database, file, array).
- `Cache::memo()` removes repeated cache round-trips within one request or job.
- **Rate limiting** uses the default cache store unless `cache.limiter` is set, e.g. `'limiter' => 'redis'`. With redis, memcached or database, `RateLimiter::increment()` is atomic, so check its return value instead of `tooManyAttempts()` + `increment()`.

## Raw Redis

- `Redis::pipeline(fn ($pipe) => …)` batches many commands into one round-trip. `Redis::transaction(fn ($redis) => …)` is MULTI/EXEC: you can't read values inside it. Use `Redis::eval()` (Lua) for read-modify-write atomicity.
- **Never `KEYS *` in application code** *(practice)*: it blocks the server while it walks every key. Use `SCAN` (`Redis::scan()`), tags, or a key-set you maintain.
- **Always set a TTL on keys you create directly** *(practice)*. Unbounded keys are how a Redis instance quietly fills up and starts evicting what matters.
- Queues on Redis: `retry_after` must be longer than your longest job, or jobs run twice *(practice)*; Horizon if it's installed.

## Testing

Use the `array` cache store in tests (`CACHE_STORE=array` in `phpunit.xml`), and `Cache::spy()` / `Cache::shouldReceive()` to assert invalidation. Don't depend on a live Redis in the test suite unless the project already does.
