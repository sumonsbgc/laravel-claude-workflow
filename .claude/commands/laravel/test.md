---
description: Write or repair tests for a file, feature, or failing suite
argument-hint: [what to test, or blank for the current changes]
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, Skill
---

Target: **$ARGUMENTS** (blank = the current uncommitted changes)

Delegate to `laravel-test-writer` unless this is a one-file change you can cover in a couple of tests yourself.

Load `laravel-conventions/references/testing.md`. Read `tests/Pest.php` (or `TestCase.php`) and one existing test before writing, so the new tests match the suite's style and traits.

## What to cover, in this order

1. **Authorization** — the user who may, the user who may not, and the user acting on someone else's record.
2. **Validation** — the invalid payload rejected with the right field errors; the valid one accepted.
3. **The happy path through the named route** — status, redirect target, and the database row that should now exist.
4. **State transitions and anything with dates or arithmetic**, including the boundary.

Not worth testing: that Eloquent saves a column, that a view prints a literal string.

## Rules

- Hit routes by `route()` name, not by URL string.
- Factories and states, never hand-inserted rows or seeder ids.
- Fake the boundaries: `Queue::fake()`, `Mail::fake()`, `Storage::fake()`, `Http::fake()`.
- `freezeTime()` / `travelTo()` for date-dependent behaviour.
- A failing test is fixed by fixing the code, or by fixing a test that was genuinely wrong — never by skipping, weakening, or deleting it.

## Repairing a failing suite

Read the failure before changing anything. Decide whether the test or the code is wrong, say which, then fix that one. Run with `--filter` while iterating and the whole file at the end.

## Report

What you covered, what you deliberately did not, any bug the tests exposed, and any test you changed rather than added — with the reason.
