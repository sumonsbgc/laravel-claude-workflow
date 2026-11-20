# Layer catalog — the per-feature folder, file by file

Each feature is one folder. Each layer is one file with a fixed number, so a developer can be handed `02-Migration.md` or `09-Test.md` and nothing else. Numbering is the build order inside the feature.

## Tree

```
.claude/plans/
  README.md                 index: features, order, waves, owners, status
  00-Overview.md            goals, non-goals, roles, architecture, ADRs, feature list, graph, waves, risks
  _recon.md                 what the real repo looks like (existing apps)
  00-foundation/            greenfield only, planned first and alone
  01-<feature>/
    README.md               the contract, assumptions, skipped layers, task-id map
    01-BRD.md  (+ 01-BRD.pdf)
    02-Migration.md
    03-Model.md
    04-Service.md
    05-API_Contract.md
    06-Controller.md
    07-View.md
    08-Jobs_Events.md
    09-Test.md
    10-Security.md
    11-Performance.md
    12-Verify.md
    13-Rollout.md
    14-Observability.md     optional
  02-<next-feature>/
```

Folder numbers are dependency order. Slugs are kebab-case (`01-invoicing`).

## Layers

| File | Holds | Depth |
|---|---|---|
| **01-BRD** | Problem, goals and non-goals, actors, requirements numbered `BR-01…` each with Given/When/Then, business rules, permissions matrix, edge cases, NFRs, assumptions, open questions, traceability. Template: `templates/BRD.md`. | none (prose) |
| **02-Migration** | ERD (Mermaid), data dictionary table, migrations in dependency order, indexes with the query each serves, seeders, rollback and backfill notes | FULL CODE |
| **03-Model** | Enums, traits, models (`$fillable`, `casts()`, relations, scopes), observers, policies, factories | FULL CODE |
| **04-Service** | The business logic in the repo's own pattern: service, action, repository or DTO. Transactions, what is queued, domain exceptions | FULL CODE + acceptance criteria |
| **05-API_Contract** | The contract written before the controller: endpoints, request and response shapes, status codes, error format, auth, pagination, rate limits. For server-rendered features: routes, form fields, redirects and flash messages | tables + example payloads |
| **06-Controller** | Controllers, form requests, API resources, route registration, middleware | FULL CODE + acceptance criteria |
| **07-View** | Pages and components: states (empty, error, loading, success), validation display, accessibility, responsive behaviour | structure + key snippets |
| **08-Jobs_Events** | Events, listeners, queued jobs (`$tries`, `$timeout`, `$backoff`, idempotency), notifications, schedules | FULL CODE |
| **09-Test** | BR-xx traceability matrix and the test code: feature, unit, authorization, validation, query-count | FULL CODE |
| **10-Security** | Threat table, the control for each threat and where it lives, authorization matrix, input and output handling, rate limits, audit log, dependency audit | checklist + runnable commands, code for any control not elsewhere |
| **11-Performance** | Volume and latency targets, benchmark seeder and script, `EXPLAIN` checks, query budgets, what to do on a miss | checklist + runnable benchmark script |
| **12-Verify** | Commands with expected results, behaviour walkthrough, audit checklist a reviewer ticks | checklist + runnable commands |
| **13-Rollout** | Deploy order, flags, backfill, monitoring, rollback, first-week runbook | checklist + runnable commands |
| **14-Observability** | Log fields, metrics, alerts, dashboards, tracing — only when the feature has external calls or money | checklist |

Seeders belong to 02-Migration, factories to 03-Model, API resources to 06-Controller, so there is one obvious home for each file a dev writes.

## Skipping layers

A layer that does not apply is not written. Say so in the feature README so nobody wonders whether it was forgotten:

```
## Skipped layers
| File | Why skipped |
|---|---|
| 08-Jobs_Events | No async work: every operation finishes inside the request |
| 05-API_Contract | Server-rendered pages only; routes are in 06-Controller |
```

`01-BRD`, `02-Migration` (unless no schema change), `03-Model`, `06-Controller`, `09-Test`, `10-Security` and `12-Verify` are almost never skipped.

## Tasks inside a layer file

A layer file is split into **small tasks** of about 30 to 90 minutes and at most three files each, so one developer can finish one in a sitting and a reviewer can read it in one pass. Every task has this shape:

```
### F02.03.01 - Create the invoices table
- Owner: unassigned
- Depends on: none
- Files: database/migrations/2026_01_10_000000_create_invoices_table.php
- Estimate: 45 min

**Code**

`database/migrations/2026_01_10_000000_create_invoices_table.php`

<complete file>

**Acceptance criteria**
- [ ] `php artisan migrate --pretend` prints one `create table invoices` statement
- [ ] rolling back one step and migrating again leaves the same schema

**Verify:** `php artisan migrate --pretend`
```

- **Id** `F<feature>.<layer>.<task>`: feature number, layer file number, task number, two digits each. The id is how people say "I'm on F02.03.01".
- **The path** goes above the code block in backticks, never as a comment inside the code. The code carries no comments.
- **Code** is the complete file: no TODOs, no pseudocode, no "similar to above", no "rest of the class". A task that needs more than three files is split.
- **Status** (todo, in-progress, in-review, done, blocked) is not written in the header. It lives in the task runner (`tasks.sh`), one source of truth, so it cannot disagree with the plan. `/laravel:plan-status` shows it per wave.
- **Verify** is one exact command that fails if the task is wrong.

Short layers (a security checklist) can have one task, long ones (Model) several: one for the enum, one for the model and trait, one for observer and policy, one for the factory.

## Package footer

End each layer file with:

```
## Apply
<exact commands, in order>

## Definition of done
- [ ] <checkable item>
```

## Optional additions

Add a layer file only when the contract needs it and give it the next free number: `15-Data_Migration` (a backfill of real data), `16-Integrations` (a third-party API with webhooks), `17-Admin_Tools`. Record it in the feature README.
