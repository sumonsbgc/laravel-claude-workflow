# Changelog

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
