# Testing a Laravel app

Check the stack report for the runner. Pest and PHPUnit share the same Laravel test helpers; only the syntax differs.

## What is worth testing

In priority order — this is where the bugs actually are:

1. **Authorization branches.** The user who may, the user who may not, the user acting on someone else's record.
2. **Validation.** One test that the invalid payload is rejected with the right field errors, one that the valid one succeeds.
3. **The route's happy path.** Status, redirect target, and the database row that should now exist.
4. **State transitions.** Draft → published, and whatever is supposed to be impossible.
5. **Anything with arithmetic or date logic.** Totals, prorations, timezone boundaries, "today's edition".

Not worth testing: that Eloquent saves a column, that a Blade file renders a literal string, that a getter returns what you set.

## Feature tests

```php
it('publishes news for an editor with the permission', function () {
    $editor = User::factory()->withPermission('news.publish')->create();
    $news   = News::factory()->draft()->create();

    $this->actingAs($editor)
        ->post(route('admin.news.publish', $news))
        ->assertRedirect(route('admin.news.show', $news))
        ->assertSessionHas('status');

    expect($news->fresh()->news_status)->toBe(News::PUBLISHED);
});

it('refuses an editor without the permission', function () {
    $this->actingAs(User::factory()->create())
        ->post(route('admin.news.publish', News::factory()->draft()->create()))
        ->assertForbidden();
});
```

- Hit routes by **name** (`route(...)`), not by URL string — the test then survives a prefix change and fails properly when a route is renamed.
- Assert the database, not just the response: `assertDatabaseHas`, `assertDatabaseMissing`, `assertSoftDeleted`.
- `assertForbidden()` / `assertUnauthorized()` / `assertNotFound()` say what you mean better than `assertStatus(403)`.
- `assertSessionHasErrors(['title'])` for validation.
- Fake the boundaries: `Queue::fake()`, `Mail::fake()`, `Storage::fake('public')`, `Http::fake()`, `Event::fake()` (the last one sparingly — it disables the observers your feature may depend on).
- `travelTo(now()->setTime(23, 59))` for date-boundary behaviour, and `freezeTime()` when a test compares timestamps.

## Database

- `RefreshDatabase` in `tests/Pest.php` (or `TestCase`) for the whole Feature suite.
- Check `phpunit.xml` for the test connection. An in-memory SQLite suite is fast but does not catch MySQL-only behaviour — strict mode, enum columns, `ONLY_FULL_GROUP_BY`, JSON functions. If the app targets MySQL, at least one CI run should use it.
- Build data with factories and states. A test that inserts rows by hand encodes the schema in the test and breaks on every migration.
- Never depend on a seeder's ids, and never on test execution order.

## Unit tests

For pure logic that has no framework dependency — a formatter, a calculator, a value object. If a "unit" test needs the database, it is a feature test; move it.

## Running

Use the stack report's exact command. Narrow while iterating:

```bash
php artisan test --filter=NewsPublish
php artisan test tests/Feature/NewsTest.php
php artisan test --parallel        # needs pestphp/pest-plugin-parallel or paratest
```

A failing test is fixed by fixing the code, or by fixing a test that was genuinely wrong. Never by skipping it, weakening the assertion, or deleting it.
