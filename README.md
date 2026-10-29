# laravel-workflow

A Claude Code kit for **Laravel + Blade** projects: three skills, eight commands, eight agents,
and a set of hooks that stop the mistakes which only surface in production. Version 2.4.

It is not a Laravel application. It is a directory you install *into* one.

```bash
./install.sh /path/to/my-laravel-app     # or: ./install.sh .   from inside the project
./install.sh --global                    # every project on this machine
./install.sh . --dry-run                 # see what it would do
```

Or as a Claude Code plugin, with nothing copied into the project:

```bash
claude plugin marketplace add /path/to/laravel-workflow
claude plugin install laravel@laravel-workflow
claude plugin update laravel@laravel-workflow   # later, to upgrade
```

The commands stay `/laravel:*`. The helpers then live in the plugin's folder, not `.claude/hooks`;
the session-start report prints that path ("Kit helpers"), so use it wherever this README says
`bash .claude/hooks/…`. A plugin can't ship permission rules, so three extra hooks stand in for
them: `guard-read.sh` blocks the Read tool on env files, keys, `auth.json` and `storage/`;
`allow-helpers.sh` pre-approves the kit's own helpers (by the plugin's absolute path), the
detected verify commands with plain path arguments, a few read-only artisan commands and Boost's
read-only MCP tools; and `guard-owner.sh` blocks `verify.sh --baseline`. Every plugin hook runs
through `plugin-dispatch.sh`: guards always run, and the rest step aside when the project also
has the kit installed as files (the session report then says it is installed twice). Use one or
the other. `hooks/hooks.json` is generated from `.claude/settings.json`:
`jq -f hooks/build-hooks.jq .claude/settings.json > hooks/hooks.json`.

Then, in that project:

```
/laravel:setup                         detect the stack, seed the project memory (once)
/laravel:write-task <what you want>    planner (Opus) writes draft task files
bash .claude/hooks/tasks.sh approve all          approve the drafts you've read
/laravel:task                          build the next task (Sonnet), independently verified
bash .claude/hooks/run-tasks.sh --checkpoint     long batches: fresh session + one commit per task
/laravel:sync                          commit + pull the stage branch + check + push, in one go
```

The stage branch is set once per project: `./install.sh /path/to/app --stage-branch stage`, or
`/laravel:setup` asks. It is stored in `.claude/workflow.conf` — commit it. A plain `git push` by
Claude is always blocked; `/laravel:sync` commits, runs `git-sync.sh sync` (merges the stage branch
in, stops on conflicts), checks, then `git-sync.sh push`, which refuses a branch that doesn't
contain the stage branch's latest commit.

## Why it exists

A general-purpose agent writing Laravel makes the same handful of expensive mistakes, over and
over, because they are invisible until deployment:

- `env()` outside `config/` — null in production the moment `config:cache` runs.
- `$request->all()` into a write; authorization by role but never by *object*.
- Interpolated raw SQL; a request value used as a column name.
- N+1 in a controller or a Blade loop — fine with 5 rows, fatal with 5,000.
- `app/Http/Kernel.php` and `$this->middleware()` in controllers, neither of which exists any more.
- A cache with no invalidation path; a job dispatched inside a transaction.
- `{{ }}` inside `<script>`; a form without `@csrf`; `bg-{{ $color }}-500` that generates no CSS.

The kit encodes those as conventions the model reads, and as hooks that catch them the moment a
file is written — not three days later.

## What gets installed

```
.claude/
  agents/     laravel-route-builder  laravel-data-layer  blade-ui-builder
              laravel-test-writer    laravel-reviewer    laravel-perf-auditor
              blade-a11y-auditor     laravel-verifier
  commands/laravel/
              setup write-task task feature test review audit ship
  skills/     laravel-conventions   (http-layer, eloquent-and-data, auth-and-authorization,
                                     caching-and-queues, redis-and-cache, files-and-images,
                                     security, laravel13, testing, pitfalls)
              blade-conventions     (components, forms, alpine-and-assets, styling, block-editor)
              php-conventions       (types-and-structure, errors-and-exceptions)
  hooks/      session-context  post-edit (guard-php guard-blade guard-styles guard-editor format)
              bash-guard  guard-secrets  verify
              stack.sh  tasks.sh  run-tasks.sh  verify-browser.sh  _lib.sh
  verify.playwright.config.mjs
  templates/  task.md  tasks-readme.md  project-context.md
  settings.json                (merged, never overwritten, backed up first)
```

## What's new in 2.0

- **Plan → approve → build → verify.** `/laravel:write-task` (Opus) writes drafts with tagged acceptance criteria (`[test]`/`[browser]`/`[review]`); you approve; `/laravel:task` (Sonnet) builds; `laravel-verifier` checks the result against the task and diff only.
- **Safe batches.** `run-tasks.sh` gives every task a fresh session; `--checkpoint` makes one commit per task (never secrets, never pre-existing edits) on an `nw/batch-*` branch; `tasks.sh undo <id> [--cascade]`.
- **Laravel Boost.** When installed, agents use its read-only MCP tools (`search-docs`, `database-schema`, `last-error`, `browser-logs`, …); `/laravel:setup` recommends it when absent.
- **Verified references** (laravel.com 13.x): Laravel 13 changes, Redis and caching, uploads/S3/CDN/images, security.
- **Post/Page content uses the Gutenberg block editor** (`@wordpress/block-editor` island), never CKEditor/TinyMCE; a guard flags violations.
- **Hardening.** Injection-safe detection, narrowed permissions, secrets guard, shell-write guard, static-analysis baseline, metrics (`tasks.sh stats`), eval harness proven against a real Laravel 13 app.

## The hooks

| Hook | When | What it does |
|---|---|---|
| `session-context.sh` | SessionStart | Injects the detected stack — Laravel and PHP version, view layer, CSS framework and its *installed* version, drivers, test runner, the exact verify commands — plus `.claude/project-context.md` and the task counts. |
| `guard-php.sh` | after Edit/Write on `*.php` | Blocks `env()` outside `config/`, mass assignment from the raw request, interpolated raw SQL, leftover `dd()`, and slim-skeleton mistakes. Advises on N+1, missing casts and indexes, fat controllers, uninvalidated caches. |
| `guard-blade.sh` | after Edit/Write on `*.blade.php` | Blocks a POST form without `@csrf`, unescaped request data, and queries in a view. Advises on `{{ }}` inside `<script>`, `@php` blocks, missing `alt`, unbalanced directives. |
| `guard-styles.sh` | after Edit/Write | Reads the Tailwind version from `node_modules` and flags v3 leftovers, classes newer than what is installed, interpolated class names, and the missing pointer cursor v4 dropped. |
| `guard-editor.sh` | after Edit/Write | Flags CKEditor/TinyMCE/Summernote/Quill in Post/Page/News code or `package.json` — the kit rule is the Gutenberg block editor. |
| `bash-guard.sh` | after Bash | Files written by a shell command get the same guards; only violations the command introduced block. |
| `guard-secrets.sh` | before Bash | Blocks commands that read `.env*`, private keys, Passport keys or `auth.json` (a speed bump, not a boundary). |
| `guard-comments.sh` | before Edit/Write | Code written for a task carries no comments. Blocks an edit that adds a comment line (PHP, Blade, JS/TS, CSS, shell) before the file is written; comments already in the file, PHP attributes, tooling directives and type-only docblock tags are allowed. |
| `format.sh` | after Edit/Write | Runs the project's own Pint (or Prettier for JS/CSS) and records what changed. |
| `verify.sh` | Stop | `php -l` on everything that changed; optionally Pint `--test` and PHPStan — static-analysis findings that already existed are baselined, so only new ones fail. |

Every guard is a real check against the file just written, not a reminder — errors block, heuristics
advise. Turn any of them down:

```bash
LARAVEL_WF_PHP_GUARD=warn|off       LARAVEL_WF_BLADE_GUARD=warn|off
LARAVEL_WF_STYLE_GUARD=off          LARAVEL_WF_VERIFY=off|syntax,lint,analyse
LARAVEL_WF_EDITOR_GUARD=off         LARAVEL_WF_SECRETS_GUARD=off
LARAVEL_WF_COMMENT_GUARD=off        LARAVEL_WF_STAGE_BRANCH=stage    LARAVEL_WF_SYNC_MODE=merge|rebase
LARAVEL_WF_CHECKPOINT=commit        LARAVEL_WF_DEV_URL=http://localhost:8000
LARAVEL_WF_METRICS=off              LARAVEL_WF_NO_CACHE=1     LARAVEL_WF_TASKS_DIR=.claude/tasks
```

## The task runner

`/laravel:task` is the primary interface. `.claude/tasks/` holds one markdown file per task with
frontmatter (`id`, `title`, `status`, `depends`), a goal, and an acceptance list that becomes the
definition of done. The runner reads **only** the task it is running, routes by size (most tasks
are done directly; multi-layer ones are split across the agents), verifies proportionally, and
appends what it learned to `.claude/project-context.md` — which is injected at every session start,
so the next run doesn't rediscover it.

Files without frontmatter are ignored, so plans and notes can live in `.claude/tasks/` safely.

Upgrading from 2.1 or earlier, where tasks lived in `./tasks`: the helpers keep using `./tasks`
until you run `bash .claude/hooks/tasks.sh migrate`, which moves the folder. `.claude/tasks` is not
git-ignored (only `.claude/.cache/` is), so task files are committed with the project.

## Requirements

`bash`, `php`, and ideally `jq`. Everything degrades gracefully: no Pint means no formatting, no
PHPStan means no static analysis, no `jq` means the installer writes a settings file to merge by hand.
Detection never fails loudly — an undetected value comes back empty and the hook stays quiet.

## Development

```bash
./test.sh                      # 617 assertions against throwaway fixtures
./test.sh -v                   # ...and print each one
bash evals/run.sh --reference  # free: proves the eval checks against a real Laravel 13 app (5/5)
bash evals/run.sh              # real agent runs (API spend) — compare evals/results/ across changes
```

Run `./test.sh` after touching any hook or the installer; run the eval after any prompt change.
