---
description: Detect this Laravel project's stack and wire the workflow into it (CLAUDE.md stack section, tasks folder, gitignore)
argument-hint: (no arguments)
allowed-tools: Read, Write, Edit, Grep, Glob, Bash
---

Wire this Laravel agentic workflow into the current project. Run once per project.

## Steps

1. Run `bash <Kit helpers>/stack.sh` and read the detected stack. **Kit helpers** is the path in the session-start report: `.claude/hooks` for a project install, `~/.claude/hooks` for `--global`, or the plugin's own folder when the kit is installed as a plugin. Use it wherever this file says `<Kit helpers>`.
2. Read `composer.json`, `bootstrap/app.php`, `routes/*.php`, `phpunit.xml`, and list `app/`, `resources/views/` two levels deep. Read any existing `CLAUDE.md`.
3. Write or update `CLAUDE.md` in the project root, between the markers `<!-- laravel-workflow:start -->` and `<!-- laravel-workflow:end -->` (replace that block if it exists, leave everything outside it, including any `<laravel-boost-guidelines>` block, untouched). The block is a **pointer, not a copy**: the stack and verify commands come fresh from the session-start report every session, and repo conventions live in `.claude/project-context.md`. Duplicating either here only creates a copy that goes stale. Exactly:
   ```
   <!-- laravel-workflow:start -->
   This project uses laravel-workflow. The stack and verify commands are reported at session start;
   repo conventions are in .claude/project-context.md. Plan with /lw:write-task, approve drafts in your own terminal with
   tasks.sh approve (in the kit helpers folder), build with /lw:task (batches: run-tasks.sh there).
   <!-- laravel-workflow:end -->
   ```
4. Ensure `.gitignore` contains `.claude/.cache/`.
5. Run `bash <Kit helpers>/tasks.sh init` to create `.claude/tasks/` and `.claude/project-context.md`, then **seed the context file** from what you just learned: where each layer lives, the layout idiom, the authorization helper, the cache invalidation pattern, the test setup, any project-specific helper functions. One line per fact, under the existing headings, no narrative.
   This file is injected at the start of every session — it is what stops every future task from re-deriving the same facts. Keep it under ~60 lines and delete anything the stack report already covers.
6. **Laravel Boost.** If the session report says Boost is not installed, *recommend* it, but don't install it yourself: it's a dependency decision. In one short paragraph, tell the user what it adds to this kit: version-matched `search-docs`, `database-schema`, `last-error`/`read-log-entries`, `browser-logs`, and shared project rules in `.ai/rules`. Give the commands for them to run: `composer require laravel/boost --dev && php artisan boost:install`, choosing Claude Code, guidelines, skills and MCP. After that, Claude Code asks once to approve the project's `.mcp.json` server. If Boost **is** installed and `.ai/rules/index.md` doesn't exist, offer to run Boost's `infer-conventions` skill to bootstrap the project's rules (it asks before recording each one).
7. **Static-analysis baseline.** If `CMD_ANALYSE` is set and analysis currently fails, tell the user to record the existing findings by typing `! bash <Kit helpers>/verify.sh --baseline` (with the real path filled in). You may not run it yourself: an agent must never baseline findings it might have caused.
8. **Stage branch.** If the project is a git repository with a remote and `bash <Kit helpers>/git-sync.sh stage` exits 2, run `bash <Kit helpers>/git-sync.sh candidates` and ask the user which branch `/lw:sync` must pull before every push (suggested ones first; they may also say "none yet"). Record the answer with `bash <Kit helpers>/git-sync.sh stage <branch>`, and mention that `.claude/workflow.conf` should be committed.
9. **Push mode.** If the project is a git repository, ask the user once how pushing should work, with two options:
   - **Manual push (recommended).** Claude commits and syncs, but never pushes by itself. The user publishes by typing `/lw:sync` (their go-ahead for that turn) or by running `bash <Kit helpers>/git-sync.sh push` in their own terminal. Nothing to configure: this is how the guard behaves by default.
   - **Claude may push.** After finishing work, Claude runs `git-sync.sh push` by itself (never a plain `git push`, never forced, and only with the stage branch merged in). This is switched on by `LARAVEL_WF_ALLOW_PUSH=1` in the environment Claude Code is started with. It also lets Claude open and merge pull requests, so say that.

   **Never write the "Claude may push" setting yourself**: not into `.claude/settings.json`, `.claude/workflow.conf`, a shell profile or any other file. The guard trusts only the environment, which Claude cannot change; a file Claude can write would let it switch its own guard off. Show the user the line to add themselves instead: `export LARAVEL_WF_ALLOW_PUSH=1` in their shell profile, or `"env": {"LARAVEL_WF_ALLOW_PUSH": "1"}` in their **user-level** `~/.claude/settings.json` (not the project's, which a teammate or a cloned repo could set for everyone), then restart Claude Code. Do not store the answer anywhere; just report it.
10. Report: the detected stack, what you changed, and anything the workflow can't do here:
   - no Pint, no test runner or no static analysis;
   - no git, so no task diffs or checkpoints;
   - no Playwright, so `[browser]` criteria stay unverified;
   - no Boost, so no version-matched docs search.

Do not install dependencies, run migrations, or restructure the project.
