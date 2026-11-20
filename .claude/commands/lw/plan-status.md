---
description: Show progress of the planned features per wave — done, in progress, blocked, and the next runnable tasks
argument-hint: [feature slug]
model: sonnet
allowed-tools: Read, Grep, Glob, Bash
---

Feature filter: **$ARGUMENTS** (blank means every feature)

`T=<Kit helpers>/tasks.sh`, using the **Kit helpers** path from the session report. Read-only: this command changes nothing, not a task, not a plan file.

1. `bash $T list` for every task and its status. Plan-backed tasks have titles of the form `<feature> · <NN> <Layer>`; group them by feature. Tasks without that form go under "Other tasks".
2. Read `.claude/plans/00-Overview.md` for the **Parallel waves** table, and each feature's `README.md` only if the table is missing, to place features in waves. When there is no overview (a single feature), treat it as one wave.
3. Report, wave by wave, a table per feature: layer, task id, status, depends. Show a count line per feature (`done / total`).
4. Then list: **blocked** tasks with the reason from the log, tasks in **review** with what the user must check and the `accept` command to run in their own terminal, **drafts** waiting for `approve` (the command to run in their own terminal), and the **next runnable** tasks (`bash $T next` for the first; the others are those whose `depends:` are all done), grouped by wave so work can be handed out in parallel.
5. If a plan file exists with no matching task, say so and suggest `/lw:write-task` on that plan.

Never edit statuses. Keep the whole report under 60 lines.
