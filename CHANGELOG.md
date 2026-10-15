# Changelog

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
