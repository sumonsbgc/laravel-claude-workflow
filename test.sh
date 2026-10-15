#!/usr/bin/env bash
# Self-test for the laravel-workflow kit. Run it after touching any hook or the installer.
#
#   ./test.sh            run everything
#   ./test.sh -v         also print each passing assertion
#
# Builds a throwaway Laravel-shaped fixture in a temp dir; never touches a real project.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS="$KIT/.claude/hooks"
VERBOSE=0; [ "${1:-}" = "-v" ] && VERBOSE=1

PASS=0; FAIL=0; FAILED=()
ok()   { PASS=$((PASS+1)); [ "$VERBOSE" = 1 ] && printf '  ok   %s\n' "$1"; return 0; }
bad()  { FAIL=$((FAIL+1)); FAILED+=("$1"); printf '  FAIL %s\n' "$1"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected '$3', got '$2')"; fi; }
contains()   { if grep -qF -- "$2" <<<"$1"; then ok "$3"; else bad "$3 (missing: $2)"; fi; }
lacks()      { if grep -qF -- "$2" <<<"$1"; then bad "$3 (unexpectedly present: $2)"; else ok "$3"; fi; }
section(){ printf '\n%s\n' "$1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
P="$TMP/app-fixture"

# ---------------------------------------------------------------- fixture -----
mkdir -p "$P"/{app/{Http/{Controllers,Requests},Models,Services,View/Composers},config,database/migrations,resources/{views/components,css},routes,tests,bootstrap,vendor/bin,node_modules/tailwindcss,.claude}
touch "$P/artisan"
cat > "$P/composer.json" <<'EOF'
{ "require": { "php": "^8.3", "laravel/framework": "^12.0" },
  "require-dev": { "pestphp/pest": "^3.0", "laravel/pint": "^1.0" },
  "scripts": { "test": ["@php artisan test"], "dev": ["php artisan serve"] } }
EOF
cat > "$P/composer.lock" <<'EOF'
{ "packages": [ { "name": "laravel/framework", "version": "v12.4.1" } ],
  "packages-dev": [ { "name": "pestphp/pest", "version": "v3.7.0" } ] }
EOF
cat > "$P/package.json" <<'EOF'
{ "scripts": { "build": "vite build", "dev": "vite" },
  "devDependencies": { "tailwindcss": "^4.1.0" }, "dependencies": { "alpinejs": "^3.14.0" } }
EOF
echo '{"version":"4.1.0"}' > "$P/node_modules/tailwindcss/package.json"
cat > "$P/.env" <<'EOF'
APP_KEY=base64:secret-should-never-be-read
DB_CONNECTION=mysql
CACHE_STORE=redis
QUEUE_CONNECTION=database
SESSION_DRIVER=file
EOF
touch "$P/vite.config.js" "$P/routes/web.php" "$P/routes/admin.php"
printf '#!/bin/sh\nexit 0\n' > "$P/vendor/bin/pint"; chmod +x "$P/vendor/bin/pint"
printf '<?php\nreturn [\n    App\\Providers\\AppServiceProvider::class,\n];\n' > "$P/bootstrap/providers.php"

hook() { # hook <script> <file> [project]
  echo "{\"tool_input\":{\"file_path\":\"$2\"}}" | CLAUDE_PROJECT_DIR="${3:-$P}" bash "$HOOKS/$1" 2>&1
}
hook_rc() { echo "{\"tool_input\":{\"file_path\":\"$2\"}}" | CLAUDE_PROJECT_DIR="${3:-$P}" bash "$HOOKS/$1" >/dev/null 2>&1; echo $?; }

# ---------------------------------------------------------------- layout ------
section "kit layout"
for f in install.sh test.sh README.md .claude/settings.json \
         .claude/hooks/{stack,session-context,tasks,format,verify,guard-php,guard-blade,guard-styles}.sh \
         .claude/skills/{laravel-conventions,blade-conventions,php-conventions}/SKILL.md \
         templates/{task,tasks-readme,project-context}.md; do
  [ -f "$KIT/$f" ] && ok "exists: $f" || bad "missing: $f"
done
check "8 agents" "$(ls "$KIT/.claude/agents" | wc -l | tr -d ' ')" "8"
check "8 commands" "$(ls "$KIT/.claude/commands/laravel" | wc -l | tr -d ' ')" "8"
for h in "$KIT"/.claude/hooks/*.sh; do
  [ -x "$h" ] && ok "executable: $(basename "$h")" || bad "not executable: $(basename "$h")"
  bash -n "$h" 2>/dev/null && ok "parses: $(basename "$h")" || bad "syntax error: $(basename "$h")"
done
if command -v jq >/dev/null 2>&1; then
  jq empty "$KIT/.claude/settings.json" 2>/dev/null && ok "settings.json is valid JSON" || bad "settings.json is invalid JSON"
fi
for f in "$KIT"/.claude/agents/*.md "$KIT"/.claude/commands/laravel/*.md "$KIT"/.claude/skills/*/SKILL.md; do
  head -n1 "$f" | grep -q '^---$' && ok "frontmatter: $(basename "$(dirname "$f")")/$(basename "$f")" \
    || bad "no frontmatter: $f"
done
for f in "$KIT"/.claude/agents/*.md "$KIT"/.claude/skills/*/SKILL.md; do
  grep -qE '^name: ' "$f" && grep -qE '^description: ' "$f" && ok "name+description: $(basename "$f")" \
    || bad "missing name/description: $f"
done
# Every reference a SKILL.md points at must exist.
for s in "$KIT"/.claude/skills/*/SKILL.md; do
  d="$(dirname "$s")"
  for r in $(grep -oE 'references/[a-z-]+\.md' "$s" | sort -u); do
    [ -f "$d/$r" ] && ok "reference exists: $(basename "$d")/$r" || bad "dangling reference: $(basename "$d")/$r"
  done
done

# ---------------------------------------------------------------- stack -------
section "stack.sh"
OUT="$(CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_NO_CACHE=1 bash "$HOOKS/stack.sh")"
contains "$OUT" 'LARAVEL_VERSION="v12.4.1"' "detects the locked Laravel version"
contains "$OUT" 'TEST_RUNNER="pest"'        "detects Pest"
contains "$OUT" 'PINT="yes"'                "detects Pint binary"
contains "$OUT" 'TAILWIND_INSTALLED="4.1.0"' "reads the installed Tailwind version, not the range"
contains "$OUT" 'CACHE_STORE="redis"'       "reads driver keys from .env"
contains "$OUT" 'CMD_TEST="composer test"'  "prefers the composer test script"
contains "$OUT" 'CMD_BUILD="npm run build"' "detects the asset build"
contains "$OUT" 'ROUTE_FILES="admin.php,web.php"' "lists route files"
contains "$OUT" 'DIR_SERVICES="app/Services"' "detects the service layer"
lacks    "$OUT" 'secret-should-never-be-read' "never emits a secret from .env"
OUT2="$(CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/stack.sh")"
[ -f "$P/.claude/.cache/stack.env" ] && ok "writes the detection cache" || bad "no detection cache written"
contains "$OUT2" 'LARAVEL_VERSION="v12.4.1"' "cached read returns the same values"
EMPTY="$TMP/not-laravel"; mkdir -p "$EMPTY"
OUT3="$(CLAUDE_PROJECT_DIR="$EMPTY" bash "$HOOKS/stack.sh")"
contains "$OUT3" 'LARAVEL_VERSION=""' "stays quiet on a non-Laravel directory"
[ -f "$EMPTY/.claude/.cache/stack.env" ] && bad "cached a failed detection" || ok "never caches a failed detection"

# ---------------------------------------------------------------- session -----
section "session-context.sh"
OUT="$(CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/session-context.sh")"
contains "$OUT" 'hookSpecificOutput' "emits SessionStart JSON"
contains "$OUT" 'Laravel: v12.4.1'   "reports the Laravel version"
contains "$OUT" 'Formatter: pint'    "reports the formatter cleanly"
contains "$OUT" 'env()'              "warns about env() outside config"
lacks    "$OUT" 'secret-should-never-be-read' "never leaks a secret into the session report"
check "silent outside Laravel" "$(CLAUDE_PROJECT_DIR="$EMPTY" bash "$HOOKS/session-context.sh")" ""

# ---------------------------------------------------------------- guard-php ---
section "guard-php.sh"
mk() { mkdir -p "$(dirname "$P/$1")"; printf '%s' "$2" > "$P/$1"; }

mk app/Http/Controllers/BadController.php '<?php
class BadController {
    public function __construct() { $this->middleware("auth"); }
    public function store($request) {
        $k = env("KEY");
        News::create($request->all());
        DB::statement("update x set y = $z");
        dd($k);
    }
}'
OUT="$(hook guard-php.sh "$P/app/Http/Controllers/BadController.php")"
check "blocks a bad controller" "$(hook_rc guard-php.sh "$P/app/Http/Controllers/BadController.php")" "2"
contains "$OUT" 'env()' "flags env() outside config/"
contains "$OUT" '$this->middleware()' "flags controller-constructor middleware on 11+"
contains "$OUT" 'SQL injection' "flags interpolated raw SQL"
contains "$OUT" 'request->all()' "flags mass assignment"
contains "$OUT" 'Debug output' "flags leftover dd()"

mk config/services.php '<?php return ["legacy" => ["token" => env("LEGACY_TOKEN")]];'
check "allows env() inside config/" "$(hook_rc guard-php.sh "$P/config/services.php")" "0"

mk app/Models/Good.php '<?php
namespace App\Models;
class Good extends Model {
    protected $fillable = ["title"];
    protected function casts(): array { return ["is_active" => "boolean"]; }
    public function category() { return $this->belongsTo(Category::class); }
}'
check "clean model passes" "$(hook_rc guard-php.sh "$P/app/Models/Good.php")" "0"

mk app/Http/Kernel.php '<?php class Kernel {}'
OUT="$(hook guard-php.sh "$P/app/Http/Kernel.php")"
check "blocks a resurrected Http/Kernel" "$(hook_rc guard-php.sh "$P/app/Http/Kernel.php")" "2"
contains "$OUT" 'bootstrap/app.php' "points at bootstrap/app.php instead"

mk app/Providers/RouteServiceProvider.php '<?php class RouteServiceProvider {}'
check "flags an unregistered RouteServiceProvider" "$(hook_rc guard-php.sh "$P/app/Providers/RouteServiceProvider.php")" "2"
printf '<?php\nreturn [App\\Providers\\RouteServiceProvider::class];\n' > "$P/bootstrap/providers.php"
check "allows a registered RouteServiceProvider" "$(hook_rc guard-php.sh "$P/app/Providers/RouteServiceProvider.php")" "0"

mk app/Http/Controllers/SortController.php '<?php
class SortController { public function i($request) { return News::orderBy($request->sort)->get(); } }'
contains "$(hook guard-php.sh "$P/app/Http/Controllers/SortController.php")" 'column or direction' "flags a request value used as a column"
mk app/Http/Controllers/BindController.php '<?php
class BindController { public function i($request) { return News::query()->where("status", $request->get("status"))->get(); } }'
lacks "$(hook guard-php.sh "$P/app/Http/Controllers/BindController.php")" 'column or direction' "allows a request value bound as a value"

mk tests/Feature/ThingTest.php '<?php it("works", function () { dump($x); });'
check "does not police tests for dump()" "$(hook_rc guard-php.sh "$P/tests/Feature/ThingTest.php")" "0"

OUT="$(echo "{\"tool_input\":{\"file_path\":\"$P/app/Http/Controllers/BadController.php\"}}" | CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_PHP_GUARD=warn bash "$HOOKS/guard-php.sh" 2>&1)"
check "warn mode never blocks" "$(echo "{\"tool_input\":{\"file_path\":\"$P/app/Http/Controllers/BadController.php\"}}" | CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_PHP_GUARD=warn bash "$HOOKS/guard-php.sh" >/dev/null 2>&1; echo $?)" "0"
check "off mode is silent" "$(echo "{\"tool_input\":{\"file_path\":\"$P/app/Http/Controllers/BadController.php\"}}" | CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_PHP_GUARD=off bash "$HOOKS/guard-php.sh" 2>&1)" ""

# ---------------------------------------------------------------- guard-blade -
section "guard-blade.sh"
mk resources/views/bad.blade.php '<form method="POST" action="/x"><input name="a"></form>
{!! request("html") !!}
@foreach (App\Models\News::where("a", 1)->get() as $n)<p>{{ $n->t }}</p>@endforeach'
OUT="$(hook guard-blade.sh "$P/resources/views/bad.blade.php")"
check "blocks a bad view" "$(hook_rc guard-blade.sh "$P/resources/views/bad.blade.php")" "2"
contains "$OUT" '@csrf'   "flags a POST form without @csrf"
contains "$OUT" 'XSS'     "flags unescaped request data"
contains "$OUT" 'queries the database' "flags a query in a view"

mk resources/views/good.blade.php '<form method="POST" action="/x">
@csrf
<label for="t">Title</label><input id="t" name="title" value="{{ old("title") }}">
<button type="submit" class="cursor-pointer">Save</button>
</form>
<img src="{{ $u }}" alt="Front page">
<div x-data="{ items: @js($items) }"></div>'
check "clean view passes" "$(hook_rc guard-blade.sh "$P/resources/views/good.blade.php")" "0"

mk resources/views/js.blade.php '<script>const u = {{ $user }};</script>'
contains "$(hook guard-blade.sh "$P/resources/views/js.blade.php")" '@js' "suggests @js() for script interpolation"
mk resources/views/unbalanced.blade.php '@if ($a)<p>x</p>'
contains "$(hook guard-blade.sh "$P/resources/views/unbalanced.blade.php")" '@endif' "notices an unbalanced directive"
mk resources/views/comment.blade.php '{{-- {!! request("x") !!} --}}<p>ok</p>'
check "ignores rules inside a Blade comment" "$(hook_rc guard-blade.sh "$P/resources/views/comment.blade.php")" "0"

# ---------------------------------------------------------------- guard-styles
section "guard-styles.sh"
mk resources/views/style.blade.php '<div class="flex-shrink-0 bg-opacity-50"><a href="#">x</a></div>'
OUT="$(hook guard-styles.sh "$P/resources/views/style.blade.php")"
contains "$OUT" 'flex-shrink' "flags a v3 utility removed in v4"
contains "$OUT" 'slash modifier' "flags bg-opacity-*"
contains "$OUT" 'pointer cursor' "flags a link with no pointer cursor"
mk resources/views/interp.blade.php '<div class="bg-{{ $c }}-500"></div>'
contains "$(hook guard-styles.sh "$P/resources/views/interp.blade.php")" 'never sees' "flags an interpolated class name"
mk resources/views/ternary.blade.php '<div class="{{ $on ? "bg-blue-600" : "bg-gray-200" }} cursor-pointer"></div>'
check "allows a ternary between whole class names" "$(hook guard-styles.sh "$P/resources/views/ternary.blade.php")" ""
mk resources/views/newer.blade.php '<div class="scrollbar-thin cursor-pointer"></div>'
contains "$(hook guard-styles.sh "$P/resources/views/newer.blade.php")" 'v4.3' "flags a class newer than the installed version"
echo 'button { cursor: pointer; }' > "$P/resources/css/app.css"
mk resources/views/base.blade.php '<button>Save</button>'
check "silent once a base cursor rule exists" "$(hook guard-styles.sh "$P/resources/views/base.blade.php")" ""

# ---------------------------------------------------------------- format ------
section "format.sh"
mk app/Models/Dirty.php '<?php class Dirty {}'
hook format.sh "$P/app/Models/Dirty.php" >/dev/null
grep -q "Dirty.php" "$P/.claude/.cache/dirty-files" && ok "records a changed PHP file" || bad "did not record the changed file"
: > "$P/.claude/.cache/dirty-files"
hook format.sh "$P/resources/views/good.blade.php" >/dev/null
[ -s "$P/.claude/.cache/dirty-files" ] && bad "recorded a Blade file for php -l" || ok "never queues Blade for php -l"

# ---------------------------------------------------------------- verify ------
section "verify.sh"
: > "$P/.claude/.cache/dirty-files"
printf '<?php class Broken { public function x( }\n' > "$P/app/Models/Broken.php"
echo "$P/app/Models/Broken.php" > "$P/.claude/.cache/dirty-files"
RC=$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/verify.sh" >/dev/null 2>&1; echo $?)
if command -v php >/dev/null 2>&1; then check "blocks on a PHP syntax error" "$RC" "2"; else ok "skipped (no php binary)"; fi
[ -f "$P/.claude/.cache/dirty-files" ] && bad "left the dirty list behind" || ok "clears the dirty list"
echo "$P/app/Models/Broken.php" > "$P/.claude/.cache/dirty-files"
RC=$(echo '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/verify.sh" >/dev/null 2>&1; echo $?)
check "never loops on stop_hook_active" "$RC" "0"
rm -f "$P/app/Models/Broken.php"; : > "$P/.claude/.cache/dirty-files"
RC=$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_VERIFY=off bash "$HOOKS/verify.sh" >/dev/null 2>&1; echo $?)
check "off mode does nothing" "$RC" "0"

# ---------------------------------------------------------------- tasks -------
section "tasks.sh"
T() { CLAUDE_PROJECT_DIR="$P" bash "$HOOKS/tasks.sh" "$@" 2>&1; }
mkdir -p "$P/.claude/templates"; cp "$KIT"/templates/*.md "$P/.claude/templates/"
OUT="$(T init)"
contains "$OUT" "tasks/ ready" "init scaffolds tasks/"
[ -f "$P/tasks/TEMPLATE.md" ] && ok "copies TEMPLATE.md" || bad "no TEMPLATE.md"
[ -f "$P/.claude/project-context.md" ] && ok "creates project-context.md" || bad "no project-context.md"
printf -- '---\nid: 001\ntitle: First\nstatus: todo\n---\n\n## Goal\nx\n' > "$P/tasks/001-first.md"
printf -- '---\nid: 002\ntitle: Second\nstatus: todo\ndepends: 001\n---\n\n## Goal\ny\n' > "$P/tasks/002-second.md"
printf 'Just a plan someone dropped in here.\n' > "$P/tasks/notes.md"
check "counts only real tasks" "$(T count)" "2"
contains "$(T list)" "001    todo    First" "lists tasks with status"
contains "$(T list)" "[blocked by deps]" "marks a task whose dependency is unfinished"
check "next respects dependencies" "$(basename "$(T next)")" "001-first.md"
T start 001 >/dev/null; check "start sets doing" "$(T count doing)" "1"
check "next returns the in-progress task" "$(basename "$(T next)")" "001-first.md"
T "done" 001 >/dev/null; check "done sets done" "$(T count "done")" "1"
check "next unblocks the dependent task" "$(basename "$(T next)")" "002-second.md"
T log 002 "decided to reuse the existing service" >/dev/null
contains "$(cat "$P/tasks/002-second.md")" "## Log" "log appends under a Log heading"
T block 002 "needs a decision" >/dev/null
check "block sets blocked" "$(T count blocked)" "1"
contains "$(cat "$P/tasks/002-second.md")" "blocked: needs a decision" "block records the reason"
lacks "$(T list)" "notes" "ignores a file with no frontmatter"

# ---------------------------------------------------------------- install -----
section "install.sh"
OUT="$(bash "$KIT/install.sh" "$P" --dry-run 2>&1)"
contains "$OUT" "[dry-run]" "dry-run changes nothing"
contains "$OUT" "/laravel:task" "reports the installed commands"
[ -d "$P/.claude/agents" ] && bad "dry-run created directories" || ok "dry-run created nothing"
OUT="$(bash "$KIT/install.sh" "$EMPTY" 2>&1)"; RC=$?
check "refuses a non-Laravel target" "$RC" "1"
OUT="$(bash "$KIT/install.sh" "$P" 2>&1)"
check "installs 8 agents" "$(ls "$P/.claude/agents" | wc -l | tr -d ' ')" "8"
check "installs 8 commands" "$(ls "$P/.claude/commands/laravel" | wc -l | tr -d ' ')" "8"
check "installs 3 skills" "$(ls "$P/.claude/skills" | wc -l | tr -d ' ')" "3"
[ -x "$P/.claude/hooks/stack.sh" ] && ok "hooks are executable after install" || bad "hooks not executable after install"
grep -q '.claude/.cache/' "$P/.gitignore" && ok "adds .claude/.cache/ to .gitignore" || bad "did not update .gitignore"
if command -v jq >/dev/null 2>&1; then
  jq empty "$P/.claude/settings.json" && ok "installed settings.json is valid JSON" || bad "installed settings.json is invalid"
  check "hook paths are project-relative" "$(jq -r '.hooks.Stop[0].hooks[0].command' "$P/.claude/settings.json")" '$CLAUDE_PROJECT_DIR/.claude/hooks/verify.sh'
  printf '{"permissions":{"allow":["Bash(ls)"]},"env":{"FOO":"1"}}' > "$P/.claude/settings.json"
  bash "$KIT/install.sh" "$P" >/dev/null 2>&1
  contains "$(jq -r '.permissions.allow[]' "$P/.claude/settings.json")" "Bash(ls)" "merge keeps existing permissions"
  check "merge keeps existing keys" "$(jq -r '.env.FOO' "$P/.claude/settings.json")" "1"
  contains "$(jq -r '.hooks | keys[]' "$P/.claude/settings.json")" "SessionStart" "merge adds the kit's hooks"
  ls "$P/.claude/"settings.json.bak.* >/dev/null 2>&1 && ok "merge writes a backup" || bad "merge wrote no backup"
fi

# ================================================================ v2.0 ==========
# Ports of the next-workflow v2.x fixes, plus the Laravel-only additions.
H="$HOOKS"
lproj() { # lproj <dir> [laravel-version] -> minimal Laravel project
  mkdir -p "$1/app" "$1/config" "$1/bootstrap"; touch "$1/artisan"
  printf '{ "require": { "laravel/framework": "^%s.0" } }' "${2:-13}" > "$1/composer.json"
  printf '{ "packages": [ { "name": "laravel/framework", "version": "v%s.30.1" } ] }' "${2:-13}" > "$1/composer.lock"
}
gproj() { lproj "$1" "${2:-13}"; ( cd "$1" && git init -q && git config user.email t@t && git config user.name t \
  && printf '.claude/.cache/\n' > .gitignore && git add -A && git commit -qm init ); }
sec() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | CLAUDE_PROJECT_DIR="${2:-$TMP}" bash "$H/guard-secrets.sh" >/dev/null 2>&1; echo $?; }
raw() { CLAUDE_PROJECT_DIR="$1" LARAVEL_WF_NO_CACHE=1 LARAVEL_WF_FILE="$2" LARAVEL_WF_RAW=1 bash "$H/$3" 2>&1; }
rawrc() { CLAUDE_PROJECT_DIR="$1" LARAVEL_WF_NO_CACHE=1 LARAVEL_WF_FILE="$2" LARAVEL_WF_RAW=1 bash "$H/$3" >/dev/null 2>&1; echo $?; }

section "v2: commands, models, agents"
C="$KIT/.claude/commands/laravel"
for gone in route component action model; do [ -e "$C/$gone.md" ] && bad "/laravel:$gone removed" || ok "/laravel:$gone removed"; done
contains "$(sed -n 1,6p "$C/write-task.md")" "model: opus" "write-task plans on opus"
contains "$(cat "$C/write-task.md")" "Do not write or edit any source file" "write-task never implements"
contains "$(cat "$C/write-task.md")" "status: draft" "planner writes drafts"
contains "$(sed -n 1,6p "$C/task.md")" "model: sonnet" "task runs on sonnet"
contains "$(sed -n 1,6p "$C/feature.md")" "model: sonnet" "feature runs on sonnet"
contains "$(cat "$C/feature.md")" 'bash $T start <id>' "feature takes task ids"
contains "$(cat "$C/task.md")" "size: large" "task routes large tasks to feature phases"
contains "$(cat "$C/task.md")" "at most 3" "in-session batches capped"
contains "$(cat "$C/task.md")" "headless" "task has a headless mode"
contains "$(cat "$C/task.md")" "can-skip-verify" "mechanical verifier skip"
contains "$(cat "$C/task.md")" 'bash $T verdict <id>' "verdicts recorded"
contains "$(sed -n 1,6p "$KIT/.claude/agents/laravel-reviewer.md")" "model: opus" "reviewer on opus"
contains "$(sed -n 1,6p "$KIT/.claude/agents/laravel-verifier.md")" "model: sonnet" "verifier on sonnet"
lacks "$(sed -n 1,6p "$KIT/.claude/agents/laravel-verifier.md")" "Edit" "verifier cannot edit"
lacks "$(sed -n 1,6p "$KIT/.claude/agents/blade-a11y-auditor.md")" "Bash" "a11y auditor has no shell"
contains "$(cat "$C/setup.md")" "pointer, not a copy" "setup writes a pointer, not a stack copy"

section "v2: Laravel Boost"
contains "$(sed -n 1,6p "$KIT/.claude/agents/laravel-data-layer.md")" "mcp__laravel-boost__database-schema" "data layer gets Boost schema"
contains "$(sed -n 1,6p "$KIT/.claude/agents/laravel-verifier.md")" "mcp__laravel-boost__last-error" "verifier gets Boost logs"
lacks "$(cat "$KIT/.claude/agents/"*.md | grep '^tools:')" "record-rule" "no subagent can write project rules"
contains "$(cat "$KIT/.claude/settings.json")" "mcp__laravel-boost__search-docs" "Boost read-only tools pre-approved"
lacks "$(cat "$KIT/.claude/settings.json")" "record-rule" "record-rule is not pre-approved"
B="$TMP/boost"; lproj "$B"; printf '{ "require-dev": { "laravel/boost": "^2.0" }, "require": { "laravel/framework": "^13.0" } }' > "$B/composer.json"
printf '{"mcpServers":{"laravel-boost":{"command":"php","args":["artisan","boost:mcp"]}}}' > "$B/.mcp.json"
O="$(CLAUDE_PROJECT_DIR="$B" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh")"
contains "$O" "mcp__laravel-boost__" "Boost installed: session report routes to its tools"
O="$(CLAUDE_PROJECT_DIR="$TMP/l13" LARAVEL_WF_NO_CACHE=1 bash -c "true")"; lproj "$TMP/l13"
O="$(CLAUDE_PROJECT_DIR="$TMP/l13" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh")"
contains "$O" "Laravel Boost is not installed" "no Boost: session report says so"
contains "$O" "references/laravel13.md" "Laravel 13 sessions point at laravel13.md"
contains "$(cat "$C/setup.md")" "boost:install" "setup recommends Boost"

section "v2: verified references"
R="$KIT/.claude/skills/laravel-conventions/references"
for f in laravel13 redis-and-cache files-and-images security; do
  [ -f "$R/$f.md" ] && ok "reference $f.md" || bad "reference $f.md missing"
  contains "$(head -5 "$R/$f.md")" "laravel.com/docs/13.x" "$f.md cites the 13.x docs"
done
contains "$(cat "$R/laravel13.md")" "PreventRequestForgery" "CSRF rename documented"
contains "$(cat "$R/laravel13.md")" "serializable_classes" "cache serialization change documented"
contains "$(cat "$KIT/.claude/skills/laravel-conventions/SKILL.md")" "the property still works" "casts claim corrected"
contains "$(cat "$R/files-and-images.md")" "AWS_URL" "CDN via disk url"
contains "$(cat "$R/redis-and-cache.md")" "not** on \`file\`" "tags unsupported stores documented"

section "v2: Gutenberg rule for Post/Page"
E="$KIT/.claude/skills/blade-conventions/references/block-editor.md"
[ -f "$E" ] && ok "block-editor reference" || bad "block-editor reference missing"
contains "$(cat "$E")" "@wordpress/block-editor" "uses the official block editor packages"
contains "$(cat "$E")" "content_html" "renders only the sanitized column"
contains "$(cat "$C/write-task.md")" "Gutenberg block editor" "planner carries the editor rule"
contains "$(cat "$C/task.md")" "block-editor.md" "runner loads the editor reference"
G="$TMP/ed"; lproj "$G"; mkdir -p "$G/resources/views/admin/posts" "$G/resources/js"
printf '<form>@csrf<textarea name="content"></textarea><script>ClassicEditor.create(document.querySelector("textarea"))</script></form>\n' > "$G/resources/views/admin/posts/create.blade.php"
contains "$(raw "$G" "$G/resources/views/admin/posts/create.blade.php" guard-editor.sh)" "Gutenberg block editor" "CKEditor in a Post form is flagged"
printf '{ "dependencies": { "tinymce": "^7.0.0" } }' > "$G/package.json"
contains "$(raw "$G" "$G/package.json" guard-editor.sh)" "classic rich-text editor" "adding tinymce to package.json is flagged"
printf '<div class="invoice">{{ $invoice->total }}</div>\n' > "$G/resources/views/admin/invoice.blade.php"
check "unrelated views are not flagged" "$(raw "$G" "$G/resources/views/admin/invoice.blade.php" guard-editor.sh)" ""
printf '{ "dependencies": { "@wordpress/block-editor": "^18.1.0" } }' > "$G/package.json"
contains "$(CLAUDE_PROJECT_DIR="$G" LARAVEL_WF_NO_CACHE=1 bash "$H/stack.sh")" 'RICH_EDITOR="gutenberg' "stack detects the block editor"

section "v2: guards (Laravel 13, Redis, uploads)"
L="$TMP/g13"; lproj "$L"; mkdir -p "$L/app/Http/Controllers" "$L/app/Services" "$L/tests"
printf "<?php\nuse Illuminate\\\\Foundation\\\\Http\\\\Middleware\\\\VerifyCsrfToken;\n" > "$L/tests/X.php"
contains "$(raw "$L" "$L/tests/X.php" guard-php.sh)" "PreventRequestForgery" "VerifyCsrfToken flagged on 13"
printf "<?php\nclass S { function a(\$r) { return Http::get(\$request->input('url')); } }\n" > "$L/app/Services/Fetch.php"
check "SSRF from request input blocks" "$(rawrc "$L" "$L/app/Services/Fetch.php" guard-php.sh)" "2"
printf "<?php\nclass S { function a(\$request) { return Storage::download(\$request->input('path')); } }\n" > "$L/app/Services/Dl.php"
check "path traversal from request blocks" "$(rawrc "$L" "$L/app/Services/Dl.php" guard-php.sh)" "2"
printf "<?php\nclass S { function a() { foreach (Redis::keys('ads:*') as \$k) {} } }\n" > "$L/app/Services/K.php"
contains "$(raw "$L" "$L/app/Services/K.php" guard-php.sh)" "Redis::scan" "Redis KEYS flagged"
printf "<?php\nclass S { function a() { Cache::flush(); } }\n" > "$L/app/Services/F.php"
contains "$(raw "$L" "$L/app/Services/F.php" guard-php.sh)" "ignores the cache prefix" "Cache::flush flagged"
printf "<?php\nclass S { function a() { Cache::tags(['x'])->flush(); } }\n" > "$L/app/Services/T.php"
lacks "$(raw "$L" "$L/app/Services/T.php" guard-php.sh)" "ignores the cache prefix" "tag flush is not Cache::flush"
printf "<?php\nclass C { function s(\$r) { return \$r->file('f')->storeAs('u', \$r->file('f')->getClientOriginalName()); } }\n" > "$L/app/Http/Controllers/U.php"
contains "$(raw "$L" "$L/app/Http/Controllers/U.php" guard-php.sh)" "hashName" "client file name in storage flagged"
printf "<?php\nclass C { function s(\$request) { return \$request->image('a')->cover(400,400)->toWebp()->store('a'); } }\n" > "$L/app/Http/Controllers/I.php"
contains "$(raw "$L" "$L/app/Http/Controllers/I.php" guard-php.sh)" "queued job" "image processing in a controller flagged"
printf "<?php\nclass S { function a() { DB::table('t')->upsert(\$rows, [], ['v']); } }\n" > "$L/app/Services/U.php"
check "upsert with empty uniqueBy blocks on 13" "$(rawrc "$L" "$L/app/Services/U.php" guard-php.sh)" "2"
mkdir -p "$L/config"; printf "<?php return ['serializable_classes' => false];\n" > "$L/config/cache.php"
printf "<?php\nclass S { function a() { return Cache::remember('k', 60, fn () => Ad::where('a', 1)->get()); } }\n" > "$L/app/Services/O.php"
contains "$(raw "$L" "$L/app/Services/O.php" guard-php.sh)" "serializable_classes" "caching models with serializable_classes=false flagged"

section "v2: security (settings, injection, secrets)"
SETT="$(cat "$KIT/.claude/settings.json")"
lacks "$SETT" "//home" "no /home-wide read"
contains "$SETT" '"Read(./.env.*)"' "every .env.* file is denied to the Read tool"
contains "$SETT" '"Read(./.env.local)"' "real env files denied"
contains "$SETT" "oauth-*.key" "Passport keys denied"
lacks "$SETT" "vendor/bin/phpstan:*" "no phpstan prefix rule (-c loads code)"
lacks "$SETT" "npm run dev:*" "no long-running dev server rule"
I="$TMP/inj"; lproj "$I"; printf '{ "require": { "laravel/framework": "$(touch %s/pwned)" } }' "$I" > "$I/composer.json"; rm -f "$I/composer.lock"
CLAUDE_PROJECT_DIR="$I" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh" >/dev/null 2>&1
[ -e "$I/pwned" ] && bad "composer.json values are executed" || ok "composer.json values are never executed"
lproj "$I"; mkdir -p "$I/.claude/.cache"; printf 'LARAVEL_VERSION="$(touch %s/pwned2)"\n' "$I" > "$I/.claude/.cache/stack.env"; touch "$I/.claude/.cache/stack.env"
lacks "$(CLAUDE_PROJECT_DIR="$I" bash "$H/stack.sh")" "pwned2" "tampered cache ignored"
check "blocks cat .env" "$(sec 'cat .env')" "2"
check "blocks Passport key" "$(sec 'cat storage/oauth-private.key')" "2"
check "blocks composer auth.json" "$(sec 'cat auth.json')" "2"
check "blocks glob .en*" "$(sec 'cat .en*')" "2"
check "blocks quote-split" "$(sec "cat .en''v")" "2"
check "blocks a second line on the gitignore exemption" "$(sec $'echo x >> .gitignore\ncat .env')" "2"
check "allows .env.example" "$(sec 'cat .env.example')" "0"
check "allows gitignore lines" "$(sec 'echo .env >> .gitignore')" "0"
check "allows artisan" "$(sec 'php artisan route:list')" "0"

section "v2: dispatcher and shell writes"
D="$TMP/disp"; gproj "$D"; mkdir -p "$D/app/Services"
printf "<?php\nclass S { function a() { \$k = env('X'); } }\n" > "$D/app/Services/E.php"
O="$(echo "{\"tool_input\":{\"file_path\":\"$D/app/Services/E.php\"}}" | CLAUDE_PROJECT_DIR="$D" LARAVEL_WF_NO_CACHE=1 bash "$H/post-edit.sh" 2>&1)"; RC=$?
check "dispatcher blocks what guard-php blocks" "$RC" "2"
contains "$O" "env()" "dispatcher passes the guard message"
printf "<?php\nclass S { function a() { \$k = env('X'); } }\n" > "$D/app/Services/Old.php"; ( cd "$D" && git add -A && git commit -qm old )
export CLAUDE_PROJECT_DIR="$D"; bash "$H/bash-guard.sh" --snapshot; sleep 1
printf "<?php\nclass S { function a() {  \$k = env('X'); } }\n" > "$D/app/Services/Old.php"
O="$(printf '{"tool_input":{"command":"vendor/bin/pint"}}' | LARAVEL_WF_NO_CACHE=1 bash "$H/bash-guard.sh" 2>&1)"; RC=$?
check "reformatting a file with an old violation doesn't block" "$RC" "0"
contains "$O" "pre-existing" "the old violation is reported"
grep -q "Old.php" "$D/.claude/.cache/dirty-files" && ok "shell-written PHP joins the syntax-check list" || bad "shell-written PHP not queued for php -l"
printf "<?php\nclass S { function a() { \$k = env('Y'); } }\n" > "$D/app/Services/New.php"
O="$(printf '{"tool_input":{"command":"cat > x"}}' | LARAVEL_WF_NO_CACHE=1 bash "$H/bash-guard.sh" 2>&1)"; RC=$?
check "a new file with a violation blocks" "$RC" "2"
unset CLAUDE_PROJECT_DIR

section "v2: verify baseline (static analysis)"
V="$TMP/v"; lproj "$V"; mkdir -p "$V/vendor/bin" "$V/.claude/.cache"
printf '#!/bin/sh\necho "app/A.php:3:Old finding"; exit 1\n' > "$V/vendor/bin/phpstan"; chmod +x "$V/vendor/bin/phpstan"
echo "$V/app/A.php" > "$V/.claude/.cache/dirty-files"; printf '<?php\n' > "$V/app/A.php"
vstop() { echo "$V/app/A.php" > "$V/.claude/.cache/dirty-files"; printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$V" LARAVEL_WF_NO_CACHE=1 LARAVEL_WF_VERIFY=syntax,analyse bash "$H/verify.sh" 2>&1; }
O="$(vstop)"; RC=$?; check "no baseline: findings fail" "$RC" "2"
CLAUDE_PROJECT_DIR="$V" LARAVEL_WF_NO_CACHE=1 bash "$H/verify.sh" --baseline >/dev/null
O="$(vstop)"; RC=$?; check "baselined findings pass" "$RC" "0"
printf '#!/bin/sh\necho "app/A.php:9:Old finding"; echo "app/B.php:1:New finding"; exit 1\n' > "$V/vendor/bin/phpstan"
O="$(vstop)"; RC=$?; check "a new finding fails" "$RC" "2"
contains "$O" "New finding" "only the new finding is shown"
lacks "$O" "Old finding" "baselined finding hidden"
contains "$SETT" "verify.sh --baseline" "agent may not baseline its own findings"

section "v2: tasks (drafts, frontmatter, checkpoints, undo, verdicts)"
K="$TMP/k"; gproj "$K"; export CLAUDE_PROJECT_DIR="$K"
bash "$H/tasks.sh" init >/dev/null
printf '# a plan, not a task\n' > "$K/tasks/footer-plan.md"
printf -- '---\nid: 001\ntitle: Base\nstatus: draft\nsize: small\n---\n## Acceptance\n- [ ] [review] x\n' > "$K/tasks/001-a.md"
lacks "$(bash "$H/tasks.sh" list)" "footer-plan" "notes without frontmatter are not tasks"
contains "$(bash "$H/tasks.sh" next 2>&1)" "no runnable task" "drafts don't run"
bash "$H/tasks.sh" start 001 >/dev/null 2>&1; check "start refuses a draft" "$?" "1"
bash "$H/tasks.sh" approve all >/dev/null
printf 'scratch\n' > "$K/notes.txt"
bash "$H/tasks.sh" start 001 >/dev/null; printf '<?php // a\n' > "$K/app/A.php"
contains "$(bash "$H/tasks.sh" can-skip-verify 001)" "yes" "tiny all-[review] task may skip the verifier"
O="$(LARAVEL_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 001 "base")"
SH="$(git -C "$K" show --stat --format= HEAD)"
contains "$SH" "app/A.php" "checkpoint commits the task's file"
lacks "$SH" "notes.txt" "checkpoint leaves out pre-existing edits"
printf -- '---\nid: 002\ntitle: Dep\nstatus: todo\ndepends: 001\n---\n' > "$K/tasks/002-b.md"
bash "$H/tasks.sh" start 002 >/dev/null; printf 'SECRET=1\n' > "$K/.env"; printf '<?php // b\n' > "$K/app/B.php"
HEADB="$(git -C "$K" rev-parse HEAD)"
O="$(LARAVEL_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 002 "b" 2>&1)"
contains "$O" "SKIPPED" "checkpoint refuses when a secret file changed"
check "nothing committed" "$(git -C "$K" rev-parse HEAD)" "$HEADB"
rm -f "$K/.env"; LARAVEL_WF_CHECKPOINT=commit bash "$H/tasks.sh" close 002 "b" >/dev/null 2>&1
bash "$H/tasks.sh" undo 001 >/dev/null 2>&1; check "undo refuses while a dependent is done" "$?" "1"
bash "$H/tasks.sh" undo 001 --cascade >/dev/null 2>&1; check "undo --cascade succeeds" "$?" "0"
[ -e "$K/app/A.php" ] || [ -e "$K/app/B.php" ] && bad "cascade reverted both tasks" || ok "cascade reverted both tasks"
bash "$H/tasks.sh" verdict 001 FAIL 1 >/dev/null; bash "$H/tasks.sh" verdict 001 PASS 2 >/dev/null; bash "$H/tasks.sh" verdict 002 PASS 1 >/dev/null
contains "$(bash "$H/tasks.sh" stats)" "first-pass 50%" "stats shows verifier first-pass rate"
contains "$(cat "$K/.claude/.cache/metrics.jsonl")" '"via":"session"' "task starts tagged session/runner"
O="$(bash "$H/run-tasks.sh" --dry-run 2>&1)"
contains "$O" "/laravel:task 001 headless" "runner plans fresh sessions per task"
unset CLAUDE_PROJECT_DIR

section "v2: installer (upgrade, retired rules, version, uninstall, global)"
U="$TMP/u"; lproj "$U"; mkdir -p "$U/.claude"
cat > "$U/.claude/settings.json" <<'JSON'
{"permissions":{"allow":["Read(//home/**)","Bash(npm run dev:*)","Bash(make:*)"],"deny":["Read(./.env.*)","Read(./secrets/**)"]},
 "hooks":{"PostToolUse":[{"matcher":"Edit|Write|MultiEdit","hooks":[
  {"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-php.sh"},
  {"type":"command","command":"$CLAUDE_PROJECT_DIR/my-hook.sh"}]}]}}
JSON
bash "$KIT/install.sh" "$U" >/dev/null 2>&1
SU="$(cat "$U/.claude/settings.json")"
lacks "$SU" "//home" "upgrade removes the retired /home read rule"
lacks "$SU" "npm run dev:*" "upgrade removes other retired rules"
contains "$SU" "Bash(make:*)" "upgrade keeps the user's own rules"
contains "$SU" '"Read(./.env.*)"' "upgrade never removes a deny rule (kit's)"
contains "$SU" "Read(./secrets/**)" "upgrade never removes a deny rule (user's)"
lacks "$SU" "hooks/guard-php.sh" "upgrade drops old per-guard hook entries"
contains "$SU" "my-hook.sh" "upgrade keeps the user's hooks"
contains "$SU" "post-edit.sh" "upgrade adds the dispatcher"
check "version stamped" "$(cat "$U/.claude/laravel-workflow.version")" "$(cat "$KIT/VERSION")"
[ -f "$U/.claude/verify.playwright.config.mjs" ] && ok "verify config installed" || bad "verify config missing"
mkdir -p "$U/tasks"; touch "$U/tasks/keep.md"
bash "$KIT/install.sh" "$U" --uninstall >/dev/null 2>&1
[ -e "$U/.claude/commands/laravel" ] && bad "uninstall removes commands" || ok "uninstall removes commands"
lacks "$(cat "$U/.claude/settings.json")" "post-edit.sh" "uninstall removes kit hooks"
contains "$(cat "$U/.claude/settings.json")" "my-hook.sh" "uninstall keeps user hooks"
[ -e "$U/tasks/keep.md" ] && ok "uninstall keeps tasks/" || bad "uninstall deleted tasks/"
GH="$TMP/gh"; HOME="$GH" bash "$KIT/install.sh" --global >/dev/null 2>&1
contains "$(cat "$GH/.claude/settings.json")" "Bash(bash ~/.claude/hooks/tasks.sh:*)" "global install approves ~/.claude helpers"

section "v2: session report"
S2="$TMP/s2"; lproj "$S2"; mkdir -p "$S2/.claude"
{ printf '## Layout\n'; for i in $(seq 1 120); do printf -- '- fact %03d: services live in app/Services/Feature%03d with tests beside them\n' "$i" "$i"; done; } > "$S2/.claude/project-context.md"
O="$(CLAUDE_PROJECT_DIR="$S2" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh")"
contains "$O" "only the first 4000 were loaded" "oversized context flagged"
contains "$O" "Kit helpers" "helper path reported"
contains "$O" "Post/Page content editor" "editor rule in the report"
contains "$O" "Files: disk=" "storage line in the report"

section "v2: hook messages never execute text"
CS="$TMP/cs"; mkdir -p "$CS"; printf 'MARKER_FROM_ENV_EXAMPLE=1\n' > "$CS/.env.example"
O="$(cd "$CS" && printf '{"tool_input":{"command":"cat .env"}}' | CLAUDE_PROJECT_DIR="$CS" bash "$HOOKS/guard-secrets.sh" 2>&1)"
lacks "$O" "MARKER_FROM_ENV_EXAMPLE" "guard-secrets message runs no command substitution"

section "v2: eval harness"
EV="$KIT/evals"
for id in 001 002 003 004 005; do [ -f "$EV/checks/$id.sh" ] && ok "eval check $id" || bad "eval check $id missing"; done
contains "$(cat "$EV/checks/003.sh")" "AdminNewsHiddenTest" "authorization tested by a hidden Pest test"
contains "$(cat "$EV/hidden/AdminNewsHiddenTest.php")" "positive control" "authorization test has a positive control"
contains "$(cat "$EV/checks/005.sh")" "blocked" "ambiguous task must block"
contains "$(cat "$EV/run.sh")" "--reference" "harness can prove its checks"
ls "$EV"/results/*-reference.json >/dev/null 2>&1 && ok "a reference run is on record" || bad "no reference run on record"
bash -n "$EV/run.sh" && ok "run.sh parses" || bad "run.sh does not parse"

section "v2: security review — cached commands and task diffs"
CI="$TMP/ci"; lproj "$CI"; mkdir -p "$CI/.claude/.cache" "$CI/app"
printf 'LARAVEL_VERSION="v13.0.0"\nCMD_ANALYSE="true > %s/pwned"\n' "$CI" > "$CI/.claude/.cache/stack.env"
echo "$CI/app/A.php" > "$CI/.claude/.cache/dirty-files"; printf '<?php\n' > "$CI/app/A.php"
printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$CI" LARAVEL_WF_VERIFY=syntax,analyse bash "$H/verify.sh" >/dev/null 2>&1
[ -e "$CI/pwned" ] && bad "a tampered cached command was executed" || ok "a tampered cached command is never executed"
lacks "$(CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_NO_CACHE=1 bash "$H/stack.sh" | grep '^CMD_')" "|" "commands are written in the strict charset"
SD2="$TMP/sd2"; mkdir -p "$SD2/tasks"; ( cd "$SD2" && git init -q && git config user.email t@t && git config user.name t && echo "SECRET=old" > .env && printf -- '---\nid: 001\ntitle: x\nstatus: todo\n---\n' > tasks/001-x.md && git add -A && git commit -qm i )
CLAUDE_PROJECT_DIR="$SD2" bash "$H/tasks.sh" start 001 >/dev/null; echo "SECRET=new-value" > "$SD2/.env"
O="$(CLAUDE_PROJECT_DIR="$SD2" bash "$H/tasks.sh" diff 001)"
lacks "$O" "new-value" "task diff never prints a secret file's content"
contains "$O" "secret files changed" "task diff names the changed secret file"

section "v2: security review — cache keys and quoted cp"
KEYS_RE="$(sed -n "s/^CACHE_KEYS='\(.*\)'$/\1/p" "$H/stack.sh")"
MISSING="$(CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_NO_CACHE=1 bash "$H/stack.sh" | sed -n 's/^\([A-Z_]*\)=.*/\1/p' | grep -v '^DESIGN_SKILL$' | grep -vxE "$KEYS_RE" || true)"
check "every key stack.sh writes is in the cache allow-list" "$MISSING" ""
CK="$TMP/ck"; lproj "$CK"; mkdir -p "$CK/.claude/.cache"
printf 'LARAVEL_VERSION="v13.0.0"\nPATH="/nonexistent"\n' > "$CK/.claude/.cache/stack.env"; touch "$CK/.claude/.cache/stack.env"
lacks "$(CLAUDE_PROJECT_DIR="$CK" bash "$H/stack.sh")" "/nonexistent" "a cache that sets PATH is rejected"
QC="$TMP/qc"; mkdir -p "$QC"; echo SECRET > "$QC/.env.local"
check "quoted cp onto an existing .env.local is blocked" "$(cd "$QC" && sec 'cp .env.example ".env.local"' "$QC")" "2"

section "v2: secrets guard — brace expansion and ANSI-C quoting"
check "blocks brace expansion .{e,x}nv" "$(sec 'cat .{e,x}nv')" "2"
check "blocks ANSI-C octal" "$(sec "cat \$'.e\\156v'")" "2"
check "blocks ANSI-C hex" "$(sec "cat \$'\\x2eenv'")" "2"
check "ordinary brace lists still pass" "$(sec 'ls src/{a,b}.ts')" "0"

section "v2: secrets guard — fails closed, without over-blocking"
PAD="$(printf "\$'a' %.0s" $(seq 1 40))"
check "40 decoy \$'…' segments can't push a secret past the cap" "$(sec "echo $PAD; cat \$'.e\\156v'")" "2"
check "an unterminated \$' is blocked" "$(sec "cat \$'abc\\")" "2"
check "brace list inside a subshell is expanded" "$(sec 'cat $(echo .{e,x}nv)')" "2"
check "jq object braces pass" "$(sec "jq 'map({id})' f.json")" "0"
check "php -r code with braces passes" "$(sec "php -r 'foreach([1,2] as \$a){echo \$a;}'")" "0"
check "awk program passes" "$(sec "awk '{print \$1}' f")" "0"

section "v2: secrets guard — bounded work (a timed-out hook doesn't block)"
S0=$(date +%s); R="$(sec 'cat .env {1..99999999}')"; S1=$(date +%s)
check "a huge brace range can't time the guard out (and .env is still caught)" "$R" "2"
[ $((S1-S0)) -lt 5 ] && ok "guard stays fast on a huge range" || bad "guard stays fast on a huge range"
S0=$(date +%s); sec 'cat {a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b} f' >/dev/null; S1=$(date +%s)
[ $((S1-S0)) -lt 5 ] && ok "guard stays fast on stacked brace lists" || bad "guard stays fast on stacked brace lists"

# ---------------------------------------------------------------- summary -----
printf '\n%s\n' "-----------------------------------------"
if [ "$FAIL" -eq 0 ]; then
  printf 'All %d assertions passed.\n' "$PASS"; exit 0
else
  printf '%d passed, %d FAILED:\n' "$PASS" "$FAIL"
  printf '  - %s\n' "${FAILED[@]}"; exit 1
fi
