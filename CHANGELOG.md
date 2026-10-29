# Changelog

## 2.4.3 — 2026-10-30
- guard-owner keeps a heredoc body out of the scan only when the rest of the first line after `<<` has no `|`, `;`, `&`, backtick or `$(`. `cat <<EOF | bash` and `cat <<EOF; …` fed the "data" body to a shell or chained another command, and the body (a `git push`, say) went unchecked (automated security review). A heredoc redirected to a file is still treated as data.

## 2.4.2 — 2026-10-30
Fixes from a second automated security review.
- Push consent no longer lives in a file. Any file the hooks can read, a Bash command can write (a name built at runtime gets past a name check), so the `push-consent.sh` UserPromptSubmit hook and its token are gone. guard-owner now reads the session transcript Claude Code writes (`transcript_path` in the hook input) and allows `git-sync.sh push` only when the user's latest typed prompt is `/laravel:sync`: a non-meta, non-sidechain user entry with `<command-name>/laravel:sync</command-name>`. Tool results, sub-agent entries and plain mentions don't count, and consent ends with the user's next prompt instead of after 30 minutes. Checked against a real session transcript. Reinstalling removes the old hook file.
- guard-owner strips a heredoc body only when the text before `<<` has no quotes, backticks, `$(`, backslash or `#`, so `echo "<<EOF"` or `true # <<EOF` can't hide the commands after it. Otherwise the whole command is scanned.

## 2.4.1 — 2026-10-30
Fixes from automated security review of 2.4.0.
- guard-owner reads a heredoc delimiter the way bash does: the whole word with its quotes removed (`<<"E"OF` is `EOF`), ended only by an exact terminator line (leading tabs only for `<<-`). With more than one heredoc, an odd delimiter, or no terminator, the whole command is scanned. Before, `cat <<"E"OF … EOF` followed by `git push` hid the push.
- Push consent is bound to the session: push-consent.sh records the session id with the time, and guard-owner accepts it only for the same session, only if it is not in the future, and only for 30 minutes. Any shell command naming the consent file is blocked (the hook script itself, `push-consent.sh`, can still be read); before, `cd .claude/.cache && date +%s > push-consent` got through.
- allow-helpers no longer builds its auto-approve list from the stack cache, which a shell command could rewrite. It approves only fixed verify commands (`composer test`, `php artisan test`, `vendor/bin/pest`, `vendor/bin/phpunit`, `vendor/bin/pint --test`, `vendor/bin/phpstan analyse`, `npm run build`), optionally followed by plain paths.

## 2.4.0 — 2026-10-30
The kit installs as a Claude Code plugin, as next-workflow 2.5 does.
- `claude plugin marketplace add /path/to/laravel-workflow` then `claude plugin install laravel@laravel-workflow`. Nothing is copied into the project; `claude plugin update` upgrades it. The plugin is named `laravel`, so the commands stay `/laravel:*`. `.claude-plugin/plugin.json` points at the existing agents, commands and skills.
- `hooks/hooks.json` is generated from `.claude/settings.json` (`jq -f hooks/build-hooks.jq .claude/settings.json > hooks/hooks.json`), so the two installs never drift; the self-test fails if it is stale. The plugin's SubagentStart matcher accepts scoped names (`laravel:laravel-verifier`).
- Every plugin hook runs through `plugin-dispatch.sh`. Guards (secrets, owner, read, bash-guard, allow-helpers) always run, so a project file can't switch one off. The other hooks step aside only when the project's own settings register the same hook; the session report then says the kit is installed twice and to keep one.
- A plugin can ship hooks but not permission rules, so two plugin-only hooks stand in for them. `guard-read.sh` blocks the Read tool on `.env*` (not `.env.example`), keys, `auth.json`, `storage/`, `~/.ssh` and `~/.aws`. `allow-helpers.sh` pre-approves the kit's helpers by the plugin's absolute path only, the `tasks.sh new` heredoc, the detected test/lint/analyse/build commands with plain path arguments (flags and `key=value` prompt), the read-only artisan commands the project install allows, and Boost's read-only MCP tools. Anything with `$`, backticks, `;`, `&`, `|`, redirects, globs or braces falls through to the normal prompt; `verify.sh` and `run-tasks.sh` are never approved.
- `guard-owner.sh` blocks `verify.sh --baseline` (a project install also has a deny rule; a plugin has only the hook) and names the helper folder actually in use when it blocks `approve`/`accept`.
- "Kit helpers" in the session report is the plugin's folder for a plugin install; the commands, the verifier, `run-tasks.sh` and `verify.sh` use that path instead of a hard-coded `.claude/hooks`. The kit version is read from the plugin's `VERSION`.
- guard-secrets: the `tasks.sh new` heredoc exemption also accepts the plugin's helper path; the block message no longer glob-expands a pattern like `.e*` into the folder's file names.
- The uninstaller removes the three plugin-only hooks too.
- **No comments — pure code.** Code written for a task carries no comments. New PreToolUse(Edit|Write|MultiEdit) hook `guard-comments.sh` blocks an edit that adds a `//`, `#`, `/* */`, prose docblock, `{{-- --}}` or `<!-- -->` line to PHP, Blade, JS/TS, Vue, CSS or shell files, before the file is written, and names the lines. Only comments the edit adds count: ones already in the file (or in `old_string`) are left alone. Allowed: PHP attributes (`#[…]`), shebangs, tooling directives (`@phpstan-ignore`, `@ts-expect-error`, `eslint-disable`, `prettier-ignore`) and type-only docblock tags (`@param array<int, string>`, `@return HasMany<Post, $this>`, `@property`). `vendor/`, `node_modules/`, `storage/` and `.claude/` are skipped. `LARAVEL_WF_COMMENT_GUARD=off` turns it off. It always runs in a plugin install. Works without jq (PHP fallback).
- The rule is in `php-conventions` (replacing "comment why, not what"), the four builder agents, `/laravel:task`, `/laravel:feature`, `/laravel:test`, the reviewer's checklist and the session report.
- Plugin build: `allow-helpers` is attached only to the Bash matcher (it has nothing to approve on Edit/Write).
- **Git: commit, pull the stage branch, push.** One command, `/laravel:sync` (user-only, `disable-model-invocation`), does the whole round: commit, pull the stage branch in, re-run the tests if anything came in, push. New helper `git-sync.sh` (`stage [<branch>]`, `candidates`, `status`, `check-staged`, `sync`, `push`) does the git work deterministically: `sync` fetches and brings in this branch's own remote commits and then the stage branch (merge by default, `SYNC_MODE=rebase` to rebase; a conflict stops with exit 3 and the file list), `push` refuses until the branch contains the stage branch's latest commit and never forces.
- The stage branch lives in `.claude/workflow.conf` (`STAGE_BRANCH=…`, committed so the team shares it). Set it with `./install.sh /path/to/app --stage-branch stage`, or `/laravel:setup` and the first `/laravel:sync` ask, suggesting `stage`/`staging`/`develop` from the remote. `LARAVEL_WF_STAGE_BRANCH`, `LARAVEL_WF_SYNC_MODE` and `LARAVEL_WF_REMOTE` override it.
- Pushing changes: the owner guard now blocks every plain `git push` (even with `LARAVEL_WF_ALLOW_PUSH=1`) and points at `git-sync.sh push`. That push runs only after the user types `/laravel:sync`: a new UserPromptSubmit hook, `push-consent.sh`, records a 30-minute consent then, and the guard blocks `git-sync.sh push` without it. Claude can't create the consent itself (any command naming it is blocked). `LARAVEL_WF_ALLOW_PUSH=1` now means "git-sync.sh push without asking". Checked end to end with the plugin: `/laravel:sync` committed, merged `origin/stage` and pushed; "commit and push" in plain words committed and was refused the push, even with `git push` allow-listed.
- The session report names the stage branch and the push rule.
- Guide PDF rewritten for 2.4 (plugin install, verdict gate, review/accept, owner guard). Its source is now `docs/guide.html`; print it with `google-chrome --headless --no-pdf-header-footer --print-to-pdf=laravel-workflow-guide.pdf docs/guide.html`.

## 2.3.0 — 2026-10-23
Verification can't be skipped, approval stays with the user, and nothing is published.
- `tasks.sh close` refuses until a verdict is recorded for the task: PASS, UNVERIFIED, or a SKIPPED that `can-skip-verify` allowed. A FAIL must be fixed and re-verified first. `LARAVEL_WF_REQUIRE_VERDICT=off` turns the gate off.
- A task closed on UNVERIFIED goes to the new status `review`, not `done`. The user checks the criteria named in its log, then runs `tasks.sh accept <id>`. Tasks that depend on it wait until then; `run-tasks.sh` moves on to independent tasks. Found in a real project, where both closed tasks had every `[browser]` criterion unverified and were still marked done.
- `tasks.sh approve` and `accept` refuse inside a Claude Code session (`CLAUDECODE=1`), so the user runs them in their own terminal. Before, `tasks.sh` was pre-approved as a whole, so Claude could approve its own drafts.
- New PreToolUse(Bash) hook `guard-owner.sh` blocks `git push` (also `git -C dir push`, `cd x && git push`, `sudo`/`timeout`/`sh -c` wrappers, quoted words), `gh pr create` and `gh pr merge`, `tasks.sh approve`/`accept`, and shell edits of a task's `status:`. A hook exit 2 blocks even when an allow rule matches (docs: permissions, "Extend permissions with hooks"), so a `Bash(git push *)` rule left in `settings.local.json` doesn't reopen it. Only words in command position count, and heredoc bodies fed to anything but a shell are data, so commit messages and scripts that mention these words pass. `LARAVEL_WF_ALLOW_PUSH=1` in the environment Claude Code was started with turns the push check off. It is a speed bump, not a boundary: a git alias or a script can still push.
- The session report counts tasks awaiting the user's check.

## 2.2.1 — 2026-10-15
- guard-secrets: the new glob shortcuts (a `*` can't match a leading dot; a bare `*` blocks only where a key file exists) now apply only to plain shell globbing. With find/rg/grep/git/tar-style matchers, `-name`/`-path`/`-g`/`--include`, dotglob/GLOBIGNORE, or a `cd`/`pushd` in the command, every pattern match blocks as before (`find . -name '*' -exec cat {} +` would have reached .env). The filesystem check resolves against the hook input's `cwd`, not the project root. Found by automated security review.

## 2.2.0 — 2026-10-15
- Task files live in `.claude/tasks/` instead of `./tasks/`, alongside the rest of the kit's project state. `tasks.sh init` scaffolds it there; `tasks.sh dir` prints the folder in use and the commands read it from there instead of hardcoding a path.
- Existing projects keep working: when `.claude/tasks` doesn't exist and `./tasks` holds the kit's `TEMPLATE.md`, the helpers use `./tasks`. `tasks.sh migrate` moves it (and warns if `.gitignore` ignores `/tasks` — `.claude/tasks` is tracked). The installer says so when it finds the old layout. `LARAVEL_WF_TASKS_DIR` still overrides everything.
- Task diffs, dirty-file snapshots and the skip-verify size check exclude whichever tasks folder is in use, not a hardcoded `tasks`.
- `tasks.sh new <id>-<kebab-title>` writes a draft task from stdin, and `/laravel:write-task` uses it. Claude Code asks the user to approve every Write/Edit under `.claude/`, and settings allow-rules can't pre-approve those writes (docs: permission modes, "Protected paths"), so writing drafts with the Write tool would mean one prompt per task. `new` accepts only a well-formed draft: a `<id>-<kebab>` name with no path, frontmatter whose `id` matches, `status: draft`, and an id that doesn't exist yet.
- guard-secrets: a quoted heredoc sent to `tasks.sh new` passes even when the task text mentions `.env` (exact shape only; heredocs into `bash`/`cat`, unquoted heredocs and anything after the closing delimiter are still checked).
- guard-secrets: globs no longer false-positive. `*` can't match a leading dot, so `-not -path '*/node_modules/*'` and `ls src/*` pass; `.e*`-style patterns still block. A bare `*` blocks only where a key file actually exists (`cat keys/*`).
- The session report counts tasks in the folder actually in use (it was still looking at `./tasks`).

## 2.1.0 — 2026-10-15
Context memory: the kit now remembers more, so each task pays less to rediscover the codebase.
- Repo map (`tasks.sh map`, `repo-map.sh`): a cached, script-generated map of the app (routes; components/modules or models with relations, controllers with actions, tables). Regenerated only when the files it covers change. On a real app (aark-epaper) it is ~1,100 tokens versus ~9,000 to read the models and routes it summarizes.
- Task handoff (`tasks.sh context <id>`): the task plus what each dependency did and which files it changed (recorded at close), so dependent tasks don't re-read code a dependency just wrote.
- Subagents get the context: a SubagentStart hook (scoped to kit agents) injects the stack report and project memory (~550 tokens) before their first prompt; before this every delegation started cold and re-explored. Per the docs this leaves the subagent's prompt cache intact.
- Compaction: SessionStart now matches `startup|resume|clear|compact|fork` explicitly, so the stack report and memory are re-injected after auto-compaction (docs: injected context is otherwise summarized away).
- The session report keeps the volatile task counts last, so the stable part stays a reusable prompt prefix; the report stays under the documented 10,000-character hook cap (tested).
- Runner rules: `context` instead of `show`, and map → grep → read.

## 2.0.6 — 2026-10-15
- The Gutenberg rule is no longer loaded into every session. It reached each session from two places: the `CLAUDE.md` block `/laravel:setup` writes, and the session-start report. Both now leave it out (the report names a rich-text editor only when one is installed). The rule still applies where Post/Page work happens: the planner when a request adds such a module, `/laravel:task`'s reference table, the builder agents, and `guard-editor.sh`. Re-run `/laravel:setup` to drop the line from an existing project's `CLAUDE.md`.

## 2.0.5 — 2026-10-15
- guard-secrets: brace ranges are sized, not skipped (automated commit review). 2.x.8 judged every `{x..y}` by letters alone, so letter ranges such as `.e{n..n}v` slipped through. Ranges now count by their real size (letters at most 58, numbers by span); small ones are expanded and checked like lists; only huge numeric ranges, which can only produce digits, fall back to the letter check; a range it cannot size counts as unsure.

## 2.0.4 — 2026-10-15
- guard-secrets: bounded work (automated commit review). A hook that times out does not block, so `cat .env {1..99999999}` previously got through by exhausting the expansion step. `{x..y}` ranges are never expanded, lists are expanded only up to 256 combinations, and more than 16 brace words in one command count as unsure; over a limit, the cheap letter check decides.

## 2.0.3 — 2026-10-15
- guard-secrets now fails closed (automated commit review): more than 32 `$'…'` segments, a segment that will not decode, an unterminated `$'`, or a brace list it cannot expand safely all count as a secret reference. Brace lists are expanded from the list part of a word, so `cat $(echo .{e,x}nv)` is caught, while code with braces (`jq 'map({id})'`, `php -r`, `awk`, `node -e`) still passes.

## 2.0.2 — 2026-10-15
- guard-secrets: brace expansion (`.{e,x}nv`) and ANSI-C quoting (`$'.e\156v'`, `$'\x2eenv'`) are decoded with bash's own rules (plain-character words only, globbing off, nothing executed) and checked like any other name (automated commit review). Names built at runtime remain the documented limit.

## 2.0.1 — 2026-10-15
Security fixes from the automated commit reviews (all reproduced first, then fixed and regression-tested):
- verify.sh: a tampered `.claude/.cache/stack.env` could inject a command through `CMD_*` values (a redirect passed the old charset and was `eval`d). Commands now use a strict charset (letters, digits, space, `._/:=-`), the cache check rejects any `CMD_` line outside it, and verify.sh refuses to eval one.
- stack.sh: the cache is accepted only if every line is one of the exact keys the script writes; a cache that sets `PATH`, `IFS`, `BASH_ENV` or anything else is rejected whole.
- tasks.sh diff: secret files (`.env*`, keys, `auth.json`) are never printed (the diff is read by an agent); their names are listed as changed.
- guard-secrets: the `cp .env.example …` exemption no longer applies to commands with quotes or backslashes (a quoted target could overwrite an existing `.env.local`); the backslash filter now matches a single backslash.

## 2.0.0 — 2026-10-15
Brings every next-workflow 2.x improvement to Laravel, plus Laravel-specific additions.

Workflow
- Commands: removed `route`, `component`, `action`, `model` (covered by `/laravel:task`); added `/laravel:write-task` (Opus planner, drafts only); `/laravel:task` and `/laravel:feature <id>` run on Sonnet; `laravel-reviewer` on Opus.
- Draft → approve gate; `size: small|large` routing; tagged acceptance criteria; independent `laravel-verifier` (task + diff only) with recorded verdicts and a mechanical skip rule.
- `run-tasks.sh`: fresh session per task, budgets, `--checkpoint` commits (task files only, never secrets) on an `nw/batch-*` branch; `tasks.sh undo [--cascade]`, `diff`, `stats`.
- Metrics (`.claude/.cache/metrics.jsonl`): verifier first-pass rate, edit-hook latency, guard hits, runner vs in-session starts.

Laravel-specific
- Laravel Boost integration: read-only MCP tools scoped per agent and pre-approved (`record-rule` never); setup recommends Boost and `infer-conventions`; session report routes to `search-docs`.
- Verified references (laravel.com 13.x): `laravel13.md`, `redis-and-cache.md`, `files-and-images.md`, `security.md`. Skill `$casts` claim corrected.
- Post/Page content uses the Gutenberg block editor (`@wordpress/block-editor` island, block grammar + sanitized `content_html`); `guard-editor.sh` flags CKEditor/TinyMCE/Summernote/Quill. Laraberg rejected (last release 2023-01-24).
- Guard rules: Laravel 13 (CSRF rename, `serializable_classes`, empty `upsert` uniqueBy), Redis `KEYS`, `Cache::flush()`, tags on unsupported stores, SSRF and path traversal from request input, client file names in storage, image processing in a request. Checked against aark-epaper: no false hard blocks.

Hardening
- Injection-safe stack detection and cache validation; dispatcher hook; shell-write guard (new violations only); secrets guard (Passport keys, `auth.json`, glob/quote obfuscation; documented as a speed bump); static-analysis baseline (agent may not create it); narrowed permissions; upgrades remove retired allow rules and never remove deny rules; version stamp; `--uninstall`.
- Eval harness: real Laravel 13 app, behaviour checks over HTTP, hidden Pest tests; reference run 5/5 and four deliberate breakages caught.
