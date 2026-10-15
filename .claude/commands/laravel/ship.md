---
description: Full pre-ship gate — tests, lint, static analysis, asset build, and the deploy steps the change needs
argument-hint: (no arguments)
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Take the current changes to a shippable state. Use the exact commands from the session-start stack report (`bash .claude/hooks/stack.sh` if you need them again).

Run in this order, and **stop at the first failure, fix it, then restart from that step**:

1. **Tests** — fix the code, or the test if the test is genuinely wrong. Never skip, weaken, or delete a test to get green.
2. **Lint** (`vendor/bin/pint --test`, if Pint is installed) — then `vendor/bin/pint` to fix. Do not hand-format.
3. **Static analysis** (if the project has PHPStan/Larastan) — fix the errors. Never add to the baseline or add an ignore comment without stating why in your report.
4. **Asset build** (if views, CSS or JS changed) — a Blade page that looks unstyled in production usually means the build never ran.

Then a fast self-review of the diff:

- Leftover `dd()`, `dump()`, `var_dump()`, `console.log`, commented-out code, TODOs without an owner.
- `env()` outside `config/`; a new closure route; a secret or a real credential in a committed file; `.env` staged.
- A migration with no `down()`; a new column with no index it needs; a cache write with no invalidation.
- Authorization: does every new write check the *object*, not just the role?

Finally, list the **deploy steps** this change requires: `php artisan migrate`, `queue:restart` (any changed job class), `config:clear`/`config:cache` (any config change), `storage:link` (a new public disk), `npm run build`. A change that needs one of these and doesn't say so is how a deploy breaks.

## Report

A short status table — step, command, pass/fail, what you fixed. Then the deploy steps, anything still broken, and anything you changed that the user should look at before committing. Do not commit or push unless explicitly asked.
