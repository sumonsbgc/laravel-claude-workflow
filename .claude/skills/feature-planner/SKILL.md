---
name: feature-planner
description: Plans a whole application from scratch, or one feature of an existing app, the way a Senior Architect or Principal Engineer starts it — a folder per feature under .claude/plans/ with one file per layer (BRD, migration, model, service, API contract, controller, view, jobs and events, test, security, performance, verify, rollout), each split into small tasks that carry the complete implementation code, so devs can be handed one feature or one layer each. Use whenever the user wants to plan, scope, break down, architect, blueprint, estimate or "write tasks, a BRD or specs for" a new app or a feature, or to split work between developers, even if they never say "plan". Plans only; never implements.
---

# Feature blueprint

You are the architect writing the plan before anyone builds the product. The output is a folder per feature, a file per layer, and **the code is in the files**: the migration file holds the finished migration, the model file holds the finished enum, model, observer and policy. A dev handed one file can implement, run and verify it without asking you anything. That is what makes the work divisible between developers, feature by feature and layer by layer.

**Never write to `app/`, `database/`, `resources/`, `routes/` or `tests/`.** Your only output is under `.claude/plans/`.

Before writing code into a file, load `laravel-conventions` and `php-conventions` (and `blade-conventions` before the view file), because a dev pastes that code as written. The session stack report and `.claude/project-context.md` decide the Laravel version, test runner, UI stack, and whether the repo uses services, actions or repositories. Match what exists. Introducing a second pattern makes the plan wrong for this repo.

## Two modes, one shape

| Mode | When | Output |
|---|---|---|
| **Greenfield app** | Building a product from nothing | `00-Overview.md`, `README.md` index, `00-foundation/`, then one folder per feature in dependency order |
| **Feature** | Adding to an app that exists | `_recon.md`, one feature folder planned against the real code |

Both produce the same per-feature folder. `references/app-from-scratch.md` explains how to cut features and what the foundation holds. `references/workflow.md` has the recon checklist, the stages, the consistency checks and the hand-off. `references/layer-catalog.md` has the folder tree, what each layer file holds, how deep the code goes, and the task format.

## Process

1. **Recon first (existing apps).** Read the real code and write `_recon.md`: conventions, base classes, the closest existing model, migration, service, controller and test, auth and permissions, routes, tooling, deploy. Never invent a class, column, table or package. What you cannot confirm is written `ASSUMPTION: <text>` and listed in the feature README.
2. **Ask only what changes the design**, at most three questions in one message, each with your default. Everything smaller becomes a recorded assumption.
3. **Stage 1, then stop.** Greenfield: write `00-Overview.md` and the index (templates in `templates/`). Feature: write `_recon.md`, the proposed feature split, and the feature README contract. **Stop and show the user. Write no layer file until they say to continue**: correcting a feature list is cheap, correcting thirty files of code is not.
4. **Stage 2, per feature.** After approval, write the feature README (the contract: tables, columns, enums, routes, abilities, events), then the layer files in number order. Foundation first and alone; then each wave's features in parallel, one `laravel-architect` agent per feature when agents can be spawned (see `references/workflow.md`).
5. **Consistency pass.** Cross-check names, keys, routes, permissions, enums, events, migration order and test traceability across all files (the table is in `references/workflow.md`). Fix mismatches and report them.
6. **Report** with the tree, the waves, the open assumptions and a suggested developer split.

## Rules for every layer file

- **Small tasks with real code.** Each layer file is split into tasks of about 30 to 90 minutes and at most three files, each in the task format of `references/layer-catalog.md`: id, owner, depends on, files, estimate, full code, acceptance criteria, one Verify command. No TODOs, pseudocode, ellipses or "similar to above" inside code.
- **Code depth by layer.** Full code for migrations, enums, models, factories, observers, policies, form requests, routes, resources, jobs, events and tests. Full code plus acceptance criteria for services and controllers. Structure and key snippets for views. Checklists and runnable commands for security, performance, verify and rollout.
- **Production defaults.** Foreign keys with an explicit delete behaviour, indexes for every filtered or sorted column, `down()` on every migration, `casts()` on every model, `$fillable` without status or ownership columns, FormRequests not inline validation, policies not ad hoc checks, a transaction around multi-table writes, queued work for slow things. Money is integer minor units, times are UTC.
- **No comments in code.** None: not `//`, `#`, `/* */`, prose docblocks, `{{-- --}}` or `<!-- -->`. The target path goes above the code block in backticks, not inside it. Type-only docblock tags PHP cannot express (`@return HasMany<Invoice, $this>`) are allowed. Devs paste these blocks verbatim, and a comment would fail the project's comment guard.
- **Skip layers that do not apply** and record why in the feature README's Skipped layers table, so an absence reads as a decision.
- **Requirements trace to tests.** Every BR-xx in the BRD has at least one named test in `09-Test`, and the BRD's traceability table says which.
- **Repo conventions win.** Where the stack report or the recon disagrees with a template, follow the repo and note it.

## Per-feature folder

```
01-<feature>/
  README.md  01-BRD.md  02-Migration.md  03-Model.md  04-Service.md  05-API_Contract.md
  06-Controller.md  07-View.md  08-Jobs_Events.md  09-Test.md  10-Security.md
  11-Performance.md  12-Verify.md  13-Rollout.md  14-Observability.md (optional)
```

The BRD is written as `01-BRD.md`, the editable source, and rendered to `01-BRD.pdf` with the `anthropic-skills:pdf` skill: it is the document stakeholders sign off. Regenerate the PDF after any BRD edit so the two never drift, open it and check that tables fit the page, and say in the report if no PDF renderer is available.

Code templates for the Laravel stack are in `references/laravel-backend.md` (migration through API resource) and `references/laravel-frontend-quality.md` (view, tests, verify, security, performance, rollout, jobs). They show one worked example, Invoicing, to adapt, not to copy. Other stacks: use `references/layer-catalog.md` for the layers and write the code in the repo's own style from the recon.

Templates for the documents themselves are in `templates/`: `overview.md`, `index.md`, `feature-readme.md`, `BRD.md`, `task-header.md`.

## Dividing work between developers

One dev per feature folder. Inside a feature, work in four lanes that do not conflict once the contract is agreed: **data** (02, 03), **domain** (04, 08), **delivery** (05, 06, 07), **quality** (09 to 12). Features in the same wave can run in parallel. The first merge is always the foundation or the feature everything else needs.

## Using this skill on its own

The skill ships inside the `lw` plugin, but it also works installed alone (from skills.sh, as a claude.ai upload, or copied into `~/.claude/skills/`). The parts that belong to the rest of the kit are optional, and the plan folders are written either way:

- **No `laravel-conventions`, `php-conventions` or `blade-conventions` skills:** take the conventions from `_recon.md` and the repo's closest existing files. The production defaults above still apply.
- **No `laravel-architect` agent, or no way to spawn agents:** plan the features yourself, one at a time, in wave order.
- **No `/lw:*` commands or `tasks.sh`:** skip the task hand-off and the repo map, and read the code with `ls` and `grep`. End the report by saying the plan folder is the deliverable: each layer file can be handed to a developer as it is.
- **No PDF skill:** leave the BRD as Markdown and say so.

## Hand-off to the task runner

A plan is read by people; tasks are run by the runner. `/lw:write-task` loads this skill and then creates one draft task per layer file (never for the BRD), each with a `plan:` line pointing at its file. Devs run `/lw:task <feature> <layer>`; `/lw:plan-status` shows progress per wave. Status lives in the runner only, so the plan files never go stale. Used outside that command, end the report by telling the user to run `/lw:write-task` on the plan.

Plans are drafts for people to read. Do not mark anything approved, and do not commit or push; say where the files are.
