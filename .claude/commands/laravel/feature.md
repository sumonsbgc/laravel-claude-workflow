---
description: Run one or more tasks through the full phased build — schema, data layer, routes, views, tests, review — with specialist agents
argument-hint: <task id> [more ids…]
model: sonnet
allowed-tools: Read, Write, Edit, Grep, Glob, Bash, Task, TodoWrite, Skill
---

Task id(s): **$ARGUMENTS**

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report (`.claude/hooks`, `~/.claude/hooks` on a global install, or the plugin's folder). This command only takes task ids. If the argument is empty or is a description instead of an id, stop and tell the user to create the task first with `/laravel:write-task <description>`.

`/laravel:task` sends `size: large` tasks here on its own; running `/laravel:feature <id>` directly forces the full build on a task of any size. The task-running rules in `/laravel:task` — token discipline, skill table, verification, memory — apply here too.

For each id, in the order given, skipping any whose dependencies aren't done (`bash $T list` shows them):

1. `bash $T start <id>` (it refuses drafts; tell the user to approve the task in their own terminal), then `bash $T show <id>`. The Acceptance list is the definition of done.
2. Run the phases below.
3. Delegate to `laravel-verifier` with the task id for an independent verdict, and record each round: `bash $T verdict <id> PASS|FAIL|UNVERIFIED <round>`. On `FAIL`, fix exactly what it lists and re-verify; after two failed rounds, `bash $T block <id> "<failing criteria>"` and stop. Never skip this: `close` refuses without a recorded verdict. On `PASS WITH UNVERIFIED`, name the unverified criteria in the close log line; the task then waits in `review` until the user runs `tasks.sh accept <id>`.
4. `bash $T close <id> "<one line: what was built and any decision made>"`. Never push or open a PR — the user publishes.
5. Add anything newly learned about the codebase to `.claude/project-context.md` (one line per fact, keep it under ~60 lines).

## Phases

Every phase writes pure code: no comments of any kind (only tooling directives and type-only docblock tags), and every agent you delegate to is told so. Each phase's output is the next phase's input. Don't run them all blindly in parallel. Skip a phase the task genuinely doesn't need (no schema change → no migration) and say so in the report.

### 1. Understand (do this yourself, no subagent)

Use the stack report and project context already in your context. Find and read the closest existing analogue in this repo — a similar route, its controller, its FormRequest, its views, its tests. Establish: where files go, the naming and layout conventions, how authorization is expressed here, how caches are invalidated, what the data layer looks like.

Then write a short plan: the URLs, the schema change (if any), the data read and written, who is allowed to do what, the screens, and the files you'll create. The task's Notes hold decisions already made — follow them. Ask only if the task is still ambiguous in a way that changes the design (who can see it, what happens on failure): one message, specific questions, before writing code.

### 2. Data layer — delegate to `laravel-data-layer`

Migrations, models, relationships, queries, the service or action class that owns the operation, caching and its invalidation, any queued job. Give it the plan and the conventions you found.

### 3. Routes and controllers — delegate to `laravel-route-builder`

Route registration, FormRequests, controllers, middleware and the per-object authorization, wired to the data layer from phase 2.

### 4. Views — delegate to `blade-ui-builder`

The views and components the routes render, using only the styling stack that's installed. If the feature introduces UI with real visual latitude — a new screen rather than another instance of an existing pattern — tell the agent to load `frontend-design` and do its planning pass first. Views render what they are given: no queries, no `env()`, no business rules in a `.blade.php` file — the data comes from phase 3's controller or a view composer.

### 5. Tests — delegate to `laravel-test-writer`

Cover the authorization branches (allowed, forbidden, someone else's record), the validation branches, the happy path through the route, and any state transition the feature introduces.

### 6. Verify and review

Run the test suite, then lint, then the asset build if views or JS changed — fixing as you go. Edit source files only with Edit/Write, never via shell commands, so the guards see every change. Then delegate to `laravel-reviewer` for a security and correctness pass over the diff, and fix anything it confirms.

## Report

Per task: the URLs added, the schema change, the files created, the authorization model, the caching strategy and what invalidates it, test coverage, and the verification results. List any deploy step the change requires (`migrate`, `queue:restart`, `config:clear`, `storage:link`). Call out explicitly anything you stubbed, assumed, or left for the user to decide. End with the next runnable task.
