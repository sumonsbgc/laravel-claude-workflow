# Workflow — recon, two stages, waves, consistency pass, hand-off

## Recon (existing apps)

Before anything is planned for an existing app, read the real code and save the findings to `.claude/plans/_recon.md`. Planning against an imagined codebase produces plans nobody can apply.

Capture, with file paths as evidence:

| Area | What to find |
|---|---|
| Stack | Laravel and PHP versions, frontend stack, database, cache and queue drivers (`composer.json`, `package.json`, stack report) |
| Conventions | Base controller and model classes, where services, actions or repositories live and the pattern in use, enum and DTO style, naming |
| Closest analogues | The most similar model, migration, controller, form request, policy, view and test, by path |
| Auth | How users, roles and permissions work; the policy convention |
| Routes | Route file layout, naming, middleware groups |
| Quality tools | Test runner, lint, static analysis, asset build commands |
| Deploy | Target, queue worker, scheduler, flags |

Use `.claude/project-context.md` and the repo map first (`bash $T map`); read files only for what they leave open. Never invent a class, column, table or package that is not in the repo. When something cannot be confirmed, write it as `ASSUMPTION: <text>`, and list every assumption in the feature README so a human can confirm it.

## Stage 1 — overview and index, then stop

Greenfield: write `00-Overview.md` from `templates/overview.md` and `README.md` (the index) from `templates/index.md`. Ask at most three questions first, only those that change the architecture, each with your default.

One feature in an existing app: write `_recon.md`, propose the feature split (one feature, or several if the request is really several), and write the feature `README.md` contract from `templates/feature-readme.md`. Skip the overview unless the request spans more than one feature.

`00-Overview.md` contains: goals, non-goals, roles, architecture, ADRs (decision, options considered, why), the feature list, a Mermaid dependency graph, parallel waves, and risks.

**Then stop and show the user the overview, the feature list, the waves and the assumptions. Do not write per-feature layer files until they say to continue.** The cost of changing a feature list is a few lines; the cost of changing it after thirty files of code is a rewrite.

## Stage 2 — the per-feature folders

After approval, generate every feature in its wave order:

- `00-foundation` first and alone, because everything else builds on its names and conventions.
- Then each wave: features in the same wave do not depend on each other, so they are planned **in parallel, one `laravel-architect` agent per feature**. Brief each agent with: the feature slug, `00-Overview.md`, `_recon.md`, the foundation contract, the contract of any feature it depends on, and the `feature-blueprint` skill. When the session cannot spawn agents, plan features one at a time in wave order.
- A single feature in an existing app is written directly.

Each feature starts with its README contract, then the layer files in number order, as in `layer-catalog.md`.

## Consistency pass

After all features are written, re-read them against their contracts and against each other. Fix every mismatch; report what you fixed.

| Check | Across |
|---|---|
| Table and column names, types and nullability | migrations, models (`$fillable`, `casts()`), factories, form requests, views, tests |
| Foreign keys and delete behaviour | migrations, relations, policies, the tests that delete |
| Migration order | a table is never referenced before its migration; cross-feature migrations respect the wave order |
| Routes | every route used in a view or test exists in the routes block, with the same name and verb |
| Permissions | every ability called in a controller or view exists in the policy and is in the permissions matrix |
| Enums | every enum case used in code, tests and views exists in the enum |
| Events | every dispatched event has its listeners, every listener's event exists |
| Contracts | API payloads in 05-API_Contract match the resources and the tests |
| Traceability | every BR-xx requirement maps to at least one named test, and every test traces to a requirement |
| Shape | no code block has a TODO, pseudocode, an ellipsis or "same as above"; every task has a Verify command |

## Hand-off to the task runner

Plans are read by people; tasks are run by the runner. `/lw:write-task` creates one draft task per layer file (never for 01-BRD), titled `<feature> · <NN> <Layer>`, with `plan:` pointing at the layer file and `depends:` chaining the layers. The map from layer to task id goes in the feature README. Developers then run `/lw:task <feature> <layer>`, and `/lw:plan-status` shows where everything stands per wave.

Status lives only in the task runner. The plan files do not carry status, so they never go stale.

Git: plans are files in the working tree. Do not commit or push them unless the user asks, and follow the repository's branch and commit conventions when they do.
