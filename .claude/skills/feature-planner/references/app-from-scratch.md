# Planning a whole application from scratch

A product is built the way a team would build it: the platform first, then vertical slices that each deliver something a user can use, in dependency order. Never plan horizontally ("all migrations, then all models") — it hides integration problems until the end and cannot be split between developers.

## 1. Write the feature map

Before any folder, list the features and what each depends on. Cut features along **user capabilities**, not technical layers: "Invoicing", "Payments", "Customer portal", not "Database" or "API".

| Test for a good cut | Why |
|---|---|
| A user can say what it lets them do | Keeps the BRD concrete |
| It can ship and be tested without the features after it | Keeps order honest |
| One or two developers can own it for a sprint | Keeps packages small |
| It owns its tables | Cross-feature writes to the same table are the source of merge pain |

If a feature is too big, split it into slices that each deliver a path (`invoicing-create-and-send`, then `invoicing-reminders`), not into layers.

## 2. 00-foundation

Everything that is not a feature but every feature needs. Written as packages with the same shape (README contract, then packages), no BRD per item beyond a short one:

| Package | Holds |
|---|---|
| `01-Project-Setup` | Laravel install, version and PHP target, composer packages with reasons, `.env.example` keys, code style and static analysis config, git hooks, branch and commit conventions |
| `02-Auth-And-Roles` | Authentication flow, user table, roles and permissions model, base policies, session and password rules |
| `03-Base-Layer` | Base model concerns, enums folder convention, service/action/repository convention with one worked example, exception handling, API response shape |
| `04-Layout-And-UI-Kit` | App layout component, navigation, form components, flash messages, error pages, Tailwind and Alpine setup |
| `05-Quality-Pipeline` | Test setup, factories convention, CI workflow, coverage and static-analysis gates |
| `06-Observability` | Logging channels, error reporting, health check, queue and scheduler setup |
| `07-Deploy` | Environments, deploy steps, backups, migrations policy |

Skip or merge items the project doesn't need. A small internal tool may fold 06 and 07 into 01.

## 3. Order the features

1. Features nothing else depends on come last; features everything depends on come first (usually the core entity: customers, products, accounts).
2. Within a level, put the highest business value first.
3. Mark features that can run in parallel once foundation is merged. These are what you hand to separate developers.

State the order in the root README as a numbered list with the reason for each position, plus a small dependency table:

```
| Feature | Depends on | Can start after |
```

## 4. Shared decisions, written once

Put these in the root README so feature packages don't re-argue them: money as integer minor units with a currency column; timestamps in UTC; soft deletes policy; id type (auto-increment, ULID); enum storage (string-backed); naming (`snake_case` tables plural, models singular); pattern for business logic (service, action or repository, one choice); audit log approach; file storage disk; queue connection.

## 5. Per feature

Each feature folder follows `layer-catalog.md` exactly. For a feature that depends on another, reference the other feature's contract (table and model names) instead of redefining it, and list the dependency in the feature README.

## 6. Size of the plan

Be complete about what the first two or three features need, and just as concrete about the rest: every feature gets a full folder, but a late feature's BRD may carry more open questions. Never leave a feature as one-line bullet; the point of the plan is that a dev can start any folder cold.
