---
description: Run a task from the .claude/tasks/ folder end to end — read it, implement it, verify it, record what was learned
argument-hint: [blank = next task | <id> [headless] | all | list | init]
model: sonnet
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Argument: **$ARGUMENTS**

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report (`.claude/hooks`, or `~/.claude/hooks` on a global install). Use it for all task bookkeeping. Never glob or read `tasks/*.md` yourself; that is what the helper is for and it costs a fraction of the tokens.

| Argument | Do |
|---|---|
| *blank* | `bash $T next` → run that one task |
| `<id>` | `bash $T path <id>` → run that task |
| `<id> headless` | run that task with **no user present** (started by `run-tasks.sh`). Never ask a question: where you would ask, `bash $T block <id> "<the question>"` and stop. |
| `all` | see **Batch mode**. |
| `list` | `bash $T list` and report it. Nothing else. |
| `init` | `bash $T init`, then report what to do next. Nothing else. |

Only files with YAML frontmatter are tasks. Plans and notes that happen to live in the tasks folder are ignored by the helper — do not run them unless the user points at one.

## Token discipline — this is a requirement, not a preference

You are running against a task list, not a conversation. The same waste repeated across twenty tasks is the difference between finishing and running out of context.

1. **The session-start report and `.claude/project-context.md` are already in your context.** Never re-derive what they say — no re-detecting the Laravel version, the test runner, the cache driver, or where controllers live.
2. **Read only the task you are running, with its dependency handoff.** `bash $T context <id>` prints the task plus what each dependency did and which files it changed. Trust that instead of re-reading those files to "see what's there". Not the other task files.
3. **Read a source file once.** If you have already read it this session, you know its contents — do not re-read to "check".
4. **Map, then grep, then read.** `bash $T map` (cached, a few hundred tokens) lists the routes, modules and models: it usually answers "where is X" with no search at all. Then one targeted grep. **Grep before you read.** `grep -rn "hasPermission" app --include=*.php -l` beats reading four candidates. `php artisan route:list --path=news` beats reading the route file.
5. **Load skills by need, not by habit** — see the table below. A Blade tweak does not need the Eloquent conventions.
6. **Delegate only what pays for itself.** A subagent starts cold and re-reads context you already have; it is worth it when the work is genuinely a separate layer with its own conventions, and a waste for a two-file change. Route by size — see **Routing**.
7. **Edit source files only with Edit/Write**, never with `sed -i`, heredocs or scripts. The guards, Pint and the syntax check run on Edit/Write; shell writes are caught after the fact and cost you a round-trip.
8. **Verify proportionally** — see **Verification**. A full suite after every one-line Blade change is minutes of wall clock for nothing.
9. **Report in tens of lines, not hundreds.** No file dumps, no restating the diff, no narrating what you are about to do.

### Which skill for which task

| The task touches | Load |
|---|---|
| a view, component, or its markup | `blade-conventions`; `references/styling.md` only if styling changes |
| **building new UI, a screen, or a visual redesign** | **`frontend-design`** (user-level skill — skip if absent), in addition to the above. Not for refactors, bug fixes, copy changes, or views whose look is dictated by existing siblings. |
| a form, validation display, or an input | `blade-conventions/references/forms.md` + `laravel-conventions/references/http-layer.md` |
| Alpine, JS, or Vite assets | `blade-conventions/references/alpine-and-assets.md` |
| a route, controller, FormRequest, or middleware | `laravel-conventions` + `references/http-layer.md` |
| a model, migration, query, or service | `laravel-conventions/references/eloquent-and-data.md` |
| a cache, job, or scheduled command | `laravel-conventions/references/caching-and-queues.md`; Redis specifics: `references/redis-and-cache.md` |
| a file upload, image, S3 or CDN URL | `laravel-conventions/references/files-and-images.md` |
| **a Post, Page, News or Article module, or any long-form content field** | **`blade-conventions/references/block-editor.md`** — the Gutenberg block editor is mandatory (never CKEditor/TinyMCE) |
| login, passwords, rate limits, signed URLs, outbound HTTP to a user-given URL | `laravel-conventions/references/security.md` |
| anything version-sensitive on Laravel 13 (CSRF, cache/session config, middleware) | `laravel-conventions/references/laravel13.md` — or Boost's `search-docs` when Boost is installed |
| anything permission- or ownership-related | `laravel-conventions/references/auth-and-authorization.md` |
| tests | `laravel-conventions/references/testing.md` |
| anything non-trivial in PHP | `php-conventions` |

Load the reference, not the whole skill, when the reference is what you need.

## Running one task

1. **Claim it.** `bash $T start <id>`. If it refuses because the task is a `draft`, stop and tell the user to review it and run `bash $T approve <id>`. Drafts are unreviewed plans.
2. **Read it.** `bash $T context <id>` (the task plus its dependencies' handoff). The Acceptance list is the definition of done — you will check each item at the end.
3. **Orient, cheaply.** From the project context you should already know where things go. If something genuinely isn't recorded there, find it with one targeted grep and read at most one existing analogue — then add what you learned to the context file at the end.
4. **Decide the shape before writing.** The files you will touch, the route and its authorization, what the data layer must expose, what the view is given. Views render; controllers stay thin; the operation lives in a service or action.
5. **Implement.** Every `[test]` criterion needs a Pest/PHPUnit test that asserts it, because the verifier will look for it. Follow the conventions; the PostToolUse guards will tell you immediately if you break an escaping, mass-assignment, `env()`, N+1 or Tailwind rule — fix what they report rather than arguing with them.
6. **Verify** — see below.
7. **Get an independent verdict.** First run `bash $T can-skip-verify <id>`.
   - It says `yes` (every criterion is `[review]` and the diff is 20 lines or fewer): check the list yourself, item by item, and record `bash $T verdict <id> SKIPPED`.
   - Otherwise delegate to `laravel-verifier` with just the task id. It reads the task and `bash $T diff <id>` itself, and never sees your reasoning. That's the point. After **every** verifier round, record it with `bash $T verdict <id> PASS|FAIL|UNVERIFIED <round>` (`PASS WITH UNVERIFIED` → `UNVERIFIED`).
   - `FAIL` → fix exactly what it lists, re-verify. After two failed rounds, `bash $T block <id> "<the failing criteria>"` and stop.
   - `PASS WITH UNVERIFIED` → close, and name the unverified `[browser]` criteria in the log line so the user can check them.
8. **Close it.** `bash $T close <id> "<one line: what you did and any decision you made>"`.
9. **Record what you learned** — see **Memory**.
9. **Record what you learned** — see **Memory**.

### Ambiguity

Proceed under a stated assumption and log it. (Headless: never ask, block with the question instead.) Stop and ask **only** when the task could reasonably mean two different things that would produce materially different work, and getting it wrong would waste the implementation. In that case ask one specific question, and ask it before writing code rather than after.

## Routing

The task's `size:` field decides first — it was set by the planner (`/laravel:write-task`), which saw the whole request:

- **`size: large`** → read `.claude/commands/laravel/feature.md` (`~/.claude/commands/laravel/feature.md` on a global install) and run its **Phases** section for this task, delegating each phase. Do the claim/close/memory steps from this file as usual. Read that file only for large tasks — it is not needed otherwise.
- **`size: small`, or no size** → judge from the task itself:
  - **One or two files, one layer** (a view, a style fix, a copy change, a validation rule) → **do it yourself**. No subagents. This is most tasks.
  - **One layer, but with its own conventions** (only the schema and queries; only tests) → delegate to that **one** agent: `laravel-data-layer`, `laravel-route-builder`, `blade-ui-builder`, or `laravel-test-writer`.
  - **Genuinely multi-layer** (migration + model + route + view + tests) despite a `small` label → treat it as large (above), and say in the log that you re-sized it.

Whenever you delegate, give the agent the conventions you already know so it does not rediscover them.
- **Review** — delegate to `laravel-reviewer` only for security-sensitive or multi-file work: anything touching authorization, mass assignment, raw SQL, or file uploads. Not for a styling task.

## Verification

Run the narrowest thing that would catch a mistake in what you changed:

| Changed | Run |
|---|---|
| a view, markup or copy only | render the route (or its feature test if one exists) |
| a controller, request, or service | the tests for that feature (`--filter`) |
| a model, migration, or query | `migrate --pretend`, then the feature tests that touch it |
| authorization, uploads, or raw SQL | the full feature suite, plus a `laravel-reviewer` pass |
| anything, before the last task of a batch | the full suite, plus lint and the asset build |

Use the exact commands from the session-start report. Fix what fails before closing the task — a task that leaves the tree broken is not done, and the next task inherits the mess. If a change needs a deploy step (`migrate`, `queue:restart`, `config:clear`, `storage:link`), say so in the report.

## Batch mode (`all`)

Every task in one conversation means context grows with each one, and by the fifth task details get compacted away and quality drops. So in-session batches are capped:

- Run **at most 3** runnable tasks this way: `bash $T next` → run it fully → close it → repeat.
- If more remain, stop and tell the user to run the rest with fresh context per task: `bash .claude/hooks/run-tasks.sh` (add `--checkpoint` for one local commit per task on its own branch, so any single task can be undone with `bash $T undo <id>`).
- Stop early if a task ends `blocked`, verification fails in a way you cannot fix, or a task needs a decision only the user can make. Report which tasks completed and which is stuck.
- Run the **full** verification (tests, lint, build) once at the end of the batch, not after every task.

## Memory — leave the next run cheaper than this one

Before finishing, update `.claude/project-context.md` with anything you had to discover that isn't already there: where a kind of file lives, what a helper is called, a convention you inferred, a decision you made and why, a gotcha that cost you time.

- One line per fact, under the right heading. No narrative, no history.
- **Prune while you are there.** If the file is over ~60 lines, merge duplicates and delete what is now obvious from the code. It is injected into every session, so every line costs tokens forever.
- Do not record what the stack report already detects, or what a task file already says.
- **With Laravel Boost installed:** a convention that applies to a set of paths ("all controllers extend BaseController", "money is integer cents") is a **project rule**. Record it with `mcp__laravel-boost__record-rule`, so it's committed to `.ai/rules` and shared with the team. Layout facts (where things live, helper names) still go in `project-context.md`. Never edit `.ai/rules` by hand: Boost regenerates its index.

## Report

Short, and in this order: the task, what changed (paths only), any decision or assumption you made, verification results, any deploy step required, and what the next runnable task is. If you skipped or stubbed something, say so plainly.
