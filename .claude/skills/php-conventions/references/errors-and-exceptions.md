# Errors, exceptions and external calls

## Shapes

```php
// specific throw, at the boundary where the rule is known
if (! $news->isPublishable()) {
    throw new EditionNotPublishable("News {$news->id} has no page image.");
}

// specific catch, around the one call that can fail
try {
    $response = $this->http->post($url, $payload);
} catch (ConnectionException $e) {
    report($e);
    throw new ImportFailed('The legacy endpoint is unreachable.', previous: $e);
}
```

- The `try` wraps the call that throws, not the whole method.
- `previous:` preserves the chain — losing it means the log shows your message and none of the cause.
- Custom exceptions extend `\RuntimeException` (or `\DomainException`) and live in `app/Exceptions/`.

## Rendering

Configure once in `bootstrap/app.php`:

```php
->withExceptions(function (Exceptions $e) {
    $e->render(fn (EditionNotPublishable $ex) => back()->withErrors(['edition' => $ex->getMessage()]));
    $e->dontReport(ImportSkipped::class);
})
```

An exception with a `render()` method on the class itself works too. Either way, the controller stays free of `try`/`catch` for domain failures.

`abort(403)` / `abort(404)` / `abort(422, $message)` for HTTP outcomes — the handler formats them for HTML and JSON correctly, which a hand-built response will not.

## Never

- An empty `catch {}`.
- `catch (\Throwable $e) { return null; }` — the caller now cannot tell "no result" from "it broke".
- `@` suppression.
- Logging and continuing with state you know is invalid.
- `dd()`, `dump()`, `var_dump()` anywhere outside a debugging session. They halt or corrupt the response in production.

## Logging

- `Log::info()` for events you would want in a timeline; `Log::error()` for failures; `Log::debug()` for development detail.
- Structured context, not interpolation: `Log::error('Import failed', ['edition' => $date, 'exception' => $e])`.
- Never log credentials, tokens, full request bodies, or personal data you would not want in a log aggregator.
- One log line per failure. A method that logs at three levels on the way out produces noise nobody reads.

## External calls

Every HTTP call fails eventually — the question is what happens when it does.

```php
$response = Http::timeout(10)
    ->retry(3, 200, throw: false)
    ->withToken(config('services.legacy.token'))
    ->get($url);

if ($response->failed()) {
    throw new ImportFailed("Legacy API returned {$response->status()}.");
}
```

- **Always set a timeout.** The default is long enough to hold a web worker until it dies.
- Retry only idempotent calls. Retrying a payment is a second charge.
- Anything that calls out belongs in a queued job, not in the request cycle.
- Fake it in tests (`Http::fake()`); a test suite that makes real network calls is a suite that fails on a train.

## Transactions and failure

```php
DB::transaction(function () use ($data) {
    $order = Order::create($data);
    $order->items()->createMany($data['items']);
});

ProcessOrder::dispatch($order);   // after commit, never inside
```

If an exception escapes the closure the transaction rolls back — so do not catch inside it and continue, and do not put a queue dispatch, a mail send, or an HTTP call where a rollback would leave the outside world already changed.
