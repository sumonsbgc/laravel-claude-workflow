# Tasks

One file per task, run by `/lw:task`.

```
/lw:write-task <what you want>   plan it: the planner (Opus) writes draft task files
bash .claude/hooks/tasks.sh approve all      after you have read the drafts (your terminal, not Claude)
/lw:task            build the next runnable task (Sonnet)
/lw:task 003        build a specific task
/lw:feature 003     force the full phased build on task 003
/lw:task list       status of everything (cheap)
bash .claude/hooks/run-tasks.sh --checkpoint   many tasks, fresh context each, one commit per task
bash .claude/hooks/tasks.sh accept 003         after you checked what the verifier couldn't (status review)
bash .claude/hooks/tasks.sh undo 003           revert task 003's checkpoint (add --cascade for dependents)
bash .claude/hooks/tasks.sh stats              time, cost, verifier first-pass rate, guard hits
```

The `bash .claude/hooks/…` paths are for a project install. With `--global` they live in
`~/.claude/hooks/`; with the plugin, the session-start report prints the folder ("Kit helpers").

## Writing a task

Easiest: `/lw:write-task <description>` — it asks what it needs, splits the work, and sets
`size` and `depends` for you. By hand: copy `TEMPLATE.md` to `NNN-short-name.md` and fill it in
(the file must start with `---` frontmatter, or the runner ignores it).
The runner reads **only** the task it is working on, plus `.claude/project-context.md` — so
each task should stand on its own.

- **Goal** — the outcome, not the implementation. "An editor can expire an ad from the list",
  not "add a POST route that calls Ad::update".
- **Acceptance** — things someone else could verify, including who is allowed to do it and who
  is not. These become the definition of done, and the runner will not mark the task complete
  until each one holds.
- **Notes** — anything that would otherwise be guessed: constraints, decisions already made,
  what is explicitly out of scope.
- **depends** — ids that must finish first. The runner honours them and skips tasks whose
  dependencies aren't done.

Keep one task to one coherent change. A task that touches a migration, three controllers and
six views is really four tasks, and it will be implemented better as four.

Only files with YAML frontmatter (a first line of `---`) are treated as tasks. Plans, notes and
scratch files can live in this folder and will be ignored by the runner.

## Plans for whole features and apps

For a whole application, or a feature that spans layers, `/lw:write-task` uses the
`feature-planner` skill: it writes a plan folder in `.claude/plans/<NN-feature>/` (BRD, migration,
model, service, controller, view, test, verify, security, performance, each with its full code),
then one draft task per layer file, titled `<feature> · <NN> <Layer>`, with `plan:` pointing at the
layer file and `depends:` chaining the layers in order. Progress per wave: `/lw:plan-status`.

```
/lw:task invoicing model     run one layer of a feature (finds it by feature and layer name)
/lw:task invoicing 02        the same, by layer number
/lw:task invoicing           the feature runnable layers in order (3 at most per session)
/lw:task 014                 any task by id
/lw:feature invoicing        the full phased build for every task of a feature
```

Layers of one feature can be given to different developers or runs: they only wait on their
`depends:`. Tasks live in `.claude/tasks/`, plans in `.claude/plans/`; the runner reads only the former.

## What the runner does

1. Reads the task and the project context (not the whole codebase).
2. Routes by size — a small change is made directly; a multi-layer one is split across the
   specialist agents.
3. Implements, then verifies with the project's own test/lint/build commands.
4. Marks the task `done` (or `review` when some criteria could only be checked by you), appends a one-line log, and records anything newly learned about the
   codebase in `.claude/project-context.md` so the next task doesn't rediscover it.

It stops and asks only when a task is ambiguous in a way that would change the design.
Anything else it decides, states in the log, and keeps moving.

## Acceptance tags

Each criterion says how it will be proven, because an independent verifier checks it before the
task can close:

- `[test]`: a Pest/PHPUnit test must assert it (validation, policy, a redirect, a service result)
- `[browser]`: only visible in the rendered app; checked in a browser when `LARAVEL_WF_DEV_URL` is set.
  Without it they come back UNVERIFIED and the task waits in `review` for you.
- `[review]`: provable by reading the code

## Status

`draft` → (you approve) → `todo` → `doing` → `done`, or `review` → (you accept) → `done`, or `blocked`
with a reason in the log. A task cannot close without a verifier verdict. Approve and accept are yours:
they refuse to run inside Claude Code, so run them in your own terminal. Claude never pushes or opens
a pull request (a hook blocks it); commits, if any, stay local. You can edit statuses by hand at any time.
