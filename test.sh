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
# The suite stands in for the user's terminal, not a Claude Code session (approve/accept refuse there).
unset CLAUDECODE
# Sections written before the verdict gate close tasks directly; the gate has its own section below.
export LARAVEL_WF_REQUIRE_VERDICT=off

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
check "9 commands" "$(ls "$KIT/.claude/commands/laravel" | wc -l | tr -d ' ')" "9"
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
contains "$OUT" "tasks ready: .claude/tasks/" "init scaffolds .claude/tasks/"
[ -f "$P/.claude/tasks/TEMPLATE.md" ] && ok "copies TEMPLATE.md" || bad "no TEMPLATE.md"
[ -f "$P/.claude/project-context.md" ] && ok "creates project-context.md" || bad "no project-context.md"
printf -- '---\nid: 001\ntitle: First\nstatus: todo\n---\n\n## Goal\nx\n' > "$P/.claude/tasks/001-first.md"
printf -- '---\nid: 002\ntitle: Second\nstatus: todo\ndepends: 001\n---\n\n## Goal\ny\n' > "$P/.claude/tasks/002-second.md"
printf 'Just a plan someone dropped in here.\n' > "$P/.claude/tasks/notes.md"
check "counts only real tasks" "$(T count)" "2"
contains "$(T list)" "001    todo    First" "lists tasks with status"
contains "$(T list)" "[blocked by deps]" "marks a task whose dependency is unfinished"
check "next respects dependencies" "$(basename "$(T next)")" "001-first.md"
T start 001 >/dev/null; check "start sets doing" "$(T count doing)" "1"
check "next returns the in-progress task" "$(basename "$(T next)")" "001-first.md"
T "done" 001 >/dev/null; check "done sets done" "$(T count "done")" "1"
check "next unblocks the dependent task" "$(basename "$(T next)")" "002-second.md"
T log 002 "decided to reuse the existing service" >/dev/null
contains "$(cat "$P/.claude/tasks/002-second.md")" "## Log" "log appends under a Log heading"
T block 002 "needs a decision" >/dev/null
check "block sets blocked" "$(T count blocked)" "1"
contains "$(cat "$P/.claude/tasks/002-second.md")" "blocked: needs a decision" "block records the reason"
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
check "installs 9 commands" "$(ls "$P/.claude/commands/laravel" | wc -l | tr -d ' ')" "9"
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
NL=$'\n'; GP="$TMP/globs"; mkdir -p "$GP/keys" "$GP/src"; touch "$GP/keys/server.pem"
gsec() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | (cd "$GP" && CLAUDE_PROJECT_DIR="$GP" bash "$H/guard-secrets.sh" >/dev/null 2>&1); echo $?; }
check "ls */node_modules/* is not a secret" "$(gsec 'ls -d */node_modules/*')" "0"
check "ls src/* is allowed" "$(gsec 'ls src/*')" "0"
check "dot globs still block (.en*)" "$(gsec 'cat .en*')" "2"
check "cat .* still blocks" "$(gsec 'cat .*')" "2"
check "find -name '*' still blocks (find matches dotfiles)" "$(gsec "find . -name '*' -exec cat {} +")" "2"
check "find -path '*/x/*' still blocks" "$(gsec "find . -path '*/node_modules/*'")" "2"
check "rg -g '*' still blocks" "$(gsec "rg -uu -g '*' KEY")" "2"
check "cd into a key folder, then a bare *: still blocks" "$(gsec 'cd keys && cat *')" "2"
check "the check uses the hook's cwd, not the project root" "$(printf '{"cwd":"%s","tool_input":{"command":"cat *"}}' "$GP/keys" | CLAUDE_PROJECT_DIR="$GP" bash "$H/guard-secrets.sh" >/dev/null 2>&1; echo $?)" "2"
check "dotglob changes the rules: still blocks" "$(gsec 'shopt -s dotglob; cat *')" "2"
check "GLOBIGNORE changes the rules: still blocks" "$(gsec 'GLOBIGNORE=x; cat src/*')" "2"
check "a bare * blocks where a key really is" "$(gsec 'cat keys/*')" "2"
check "a draft heredoc to tasks.sh new may mention .env" "$(gsec "bash .claude/hooks/tasks.sh new 001-x <<'TASK'${NL}---${NL}never commit .env${NL}TASK")" "0"
check "a command after the heredoc still blocks" "$(gsec "bash .claude/hooks/tasks.sh new 001-x <<'TASK'${NL}x${NL}TASK${NL}cat .env")" "2"
check "an unquoted heredoc still blocks" "$(gsec "bash .claude/hooks/tasks.sh new 001-x <<TASK${NL}\$(cat .env)${NL}TASK")" "2"
check "a heredoc into bash still blocks" "$(gsec "bash <<'TASK'${NL}cat .env${NL}TASK")" "2"
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
contains "$(CLAUDE_PROJECT_DIR="$G" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh")" "Rich-text editor: gutenberg" "session report names an installed editor"
# The rule is loaded only when Post/Page work is planned or built, never into every session.
O="$(cat "$C/setup.md")"; case "$O" in *Gutenberg*) bad "setup's CLAUDE.md block mentions Gutenberg";; *) ok "setup's CLAUDE.md block leaves Gutenberg out";; esac
G2="$TMP/ed2"; lproj "$G2"
O="$(CLAUDE_PROJECT_DIR="$G2" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh")"
case "$O" in *Gutenberg*|*"Rich-text editor"*) bad "session report mentions an editor the project lacks";; *) ok "session report silent on editors when none is installed";; esac

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
printf '# a plan, not a task\n' > "$K/.claude/tasks/footer-plan.md"
printf -- '---\nid: 001\ntitle: Base\nstatus: draft\nsize: small\n---\n## Acceptance\n- [ ] [review] x\n' > "$K/.claude/tasks/001-a.md"
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
printf -- '---\nid: 002\ntitle: Dep\nstatus: todo\ndepends: 001\n---\n' > "$K/.claude/tasks/002-b.md"
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
mkdir -p "$U/.claude/tasks"; touch "$U/.claude/tasks/keep.md"
bash "$KIT/install.sh" "$U" --uninstall >/dev/null 2>&1
[ -e "$U/.claude/commands/laravel" ] && bad "uninstall removes commands" || ok "uninstall removes commands"
lacks "$(cat "$U/.claude/settings.json")" "post-edit.sh" "uninstall removes kit hooks"
contains "$(cat "$U/.claude/settings.json")" "my-hook.sh" "uninstall keeps user hooks"
[ -e "$U/.claude/tasks/keep.md" ] && ok "uninstall keeps .claude/tasks/" || bad "uninstall deleted .claude/tasks/"
GH="$TMP/gh"; HOME="$GH" bash "$KIT/install.sh" --global >/dev/null 2>&1
contains "$(cat "$GH/.claude/settings.json")" "Bash(bash ~/.claude/hooks/tasks.sh:*)" "global install approves ~/.claude helpers"

section "v2: session report"
S2="$TMP/s2"; lproj "$S2"; mkdir -p "$S2/.claude"
{ printf '## Layout\n'; for i in $(seq 1 120); do printf -- '- fact %03d: services live in app/Services/Feature%03d with tests beside them\n' "$i" "$i"; done; } > "$S2/.claude/project-context.md"
O="$(CLAUDE_PROJECT_DIR="$S2" LARAVEL_WF_NO_CACHE=1 bash "$H/session-context.sh")"
contains "$O" "only the first 4000 were loaded" "oversized context flagged"
contains "$O" "Kit helpers" "helper path reported"
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

section "v2.2: tasks folder under .claude"
TD="$TMP/td"; lproj "$TD"; mkdir -p "$TD/.claude/templates"; cp "$KIT"/templates/*.md "$TD/.claude/templates/"
check "default tasks dir" "$(CLAUDE_PROJECT_DIR="$TD" bash "$H/tasks.sh" dir)" ".claude/tasks"
CLAUDE_PROJECT_DIR="$TD" bash "$H/tasks.sh" init >/dev/null
[ -f "$TD/.claude/tasks/TEMPLATE.md" ] && ok "init writes .claude/tasks/TEMPLATE.md" || bad "init did not write .claude/tasks"
[ -e "$TD/tasks" ] && bad "init created a top-level tasks/" || ok "init leaves no top-level tasks/"
check "override wins" "$(CLAUDE_PROJECT_DIR="$TD" LARAVEL_WF_TASKS_DIR=work/plan bash "$H/tasks.sh" dir)" "work/plan"
LG="$TMP/legacy"; lproj "$LG"; mkdir -p "$LG/tasks"; cp "$KIT/templates/task.md" "$LG/tasks/TEMPLATE.md"
printf -- '---\nid: 001\ntitle: Old layout\nstatus: todo\n---\n' > "$LG/tasks/001-old.md"; printf '/tasks\n' > "$LG/.gitignore"
check "legacy ./tasks is still used" "$(CLAUDE_PROJECT_DIR="$LG" bash "$H/tasks.sh" dir)" "tasks"
contains "$(CLAUDE_PROJECT_DIR="$LG" bash "$H/tasks.sh" list)" "Old layout" "legacy tasks still list"
O="$(CLAUDE_PROJECT_DIR="$LG" bash "$H/tasks.sh" migrate 2>&1)"
contains "$O" "moved ./tasks -> .claude/tasks" "migrate moves the folder"
contains "$O" "will now show up in git" "migrate warns about the /tasks ignore rule"
[ -f "$LG/.claude/tasks/001-old.md" ] && [ ! -e "$LG/tasks" ] && ok "migrated files are in place" || bad "migrate left files behind"
contains "$(CLAUDE_PROJECT_DIR="$LG" bash "$H/tasks.sh" list)" "Old layout" "tasks list after migrate"
CLAUDE_PROJECT_DIR="$LG" bash "$H/tasks.sh" migrate >/dev/null 2>&1; check "migrate twice refuses" "$?" "1"

# tasks.sh new: drafts written by the helper (Claude Code prompts on every Write/Edit under .claude/)
NW="$TMP/newtask"; mkdir -p "$NW"; printf '{"dependencies":{"next":"16.0.0"}}' > "$NW/package.json"; touch "$NW/artisan"
nw() { CLAUDE_PROJECT_DIR="$NW" bash "$H/tasks.sh" new "$@" >/dev/null 2>&1; echo $?; }
check "new writes a draft" "$(printf -- '---\nid: 001\ntitle: Footer\nstatus: draft\n---\n' | nw 001-add-footer)" "0"
[ -f "$NW/.claude/tasks/001-add-footer.md" ] && ok "new writes into .claude/tasks" || bad "new writes into .claude/tasks"
check "new refuses an existing id" "$(printf -- '---\nid: 001\nstatus: draft\n---\n' | nw 001-dup)" "1"
check "new refuses a non-draft" "$(printf -- '---\nid: 002\nstatus: todo\n---\n' | nw 002-x)" "1"
check "new refuses a mismatched id" "$(printf -- '---\nid: 003\nstatus: draft\n---\n' | nw 002-x)" "1"
check "new refuses a path in the name" "$(printf -- '---\nid: 002\nstatus: draft\n---\n' | nw '002-../../evil')" "1"
check "new refuses text without frontmatter" "$(printf 'notes\n' | nw 002-notes)" "1"

section "v2: security review — cached commands and task diffs"
CI="$TMP/ci"; lproj "$CI"; mkdir -p "$CI/.claude/.cache" "$CI/app"
printf 'LARAVEL_VERSION="v13.0.0"\nCMD_ANALYSE="true > %s/pwned"\n' "$CI" > "$CI/.claude/.cache/stack.env"
echo "$CI/app/A.php" > "$CI/.claude/.cache/dirty-files"; printf '<?php\n' > "$CI/app/A.php"
printf '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$CI" LARAVEL_WF_VERIFY=syntax,analyse bash "$H/verify.sh" >/dev/null 2>&1
[ -e "$CI/pwned" ] && bad "a tampered cached command was executed" || ok "a tampered cached command is never executed"
lacks "$(CLAUDE_PROJECT_DIR="$P" LARAVEL_WF_NO_CACHE=1 bash "$H/stack.sh" | grep '^CMD_')" "|" "commands are written in the strict charset"
SD2="$TMP/sd2"; mkdir -p "$SD2/.claude/tasks"; ( cd "$SD2" && git init -q && git config user.email t@t && git config user.name t && echo "SECRET=old" > .env && printf -- '---\nid: 001\ntitle: x\nstatus: todo\n---\n' > .claude/tasks/001-x.md && git add -A && git commit -qm i )
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

section "v2: secrets guard — brace ranges are sized, not skipped"
check "letter range .e{n..n}v is expanded and caught" "$(sec 'cat .e{n..n}v')" "2"
check "letter range .{d..f}nv is expanded and caught" "$(sec 'cat .{d..f}nv')" "2"
check "small numeric ranges still pass" "$(sec 'ls x{1..5}.log')" "0"

section "v2: context memory — repo map, task handoff, subagents, compaction"
MP="$TMP/mp"; lproj "$MP"; mkdir -p "$MP/app/Models" "$MP/app/Http/Controllers" "$MP/routes" "$MP/database/migrations"
printf "<?php\nclass News extends Model {\n  public function category(): BelongsTo { return \$this->belongsTo(Category::class); }\n}\n" > "$MP/app/Models/News.php"
printf "<?php\nclass NewsController {}\n" > "$MP/app/Http/Controllers/NewsController.php"
printf "<?php\nRoute::get('/news', [NewsController::class, 'index']);\n" > "$MP/routes/web.php"
touch "$MP/database/migrations/2026_01_01_000000_create_news_table.php"
O="$(CLAUDE_PROJECT_DIR="$MP" bash "$H/repo-map.sh")"
contains "$O" "News — category:BelongsTo" "map lists models with relations"
contains "$O" "NewsController" "map lists controllers"
contains "$O" "news" "map lists tables from migrations"
contains "$O" "/news" "map lists routes (grep fallback without vendor)"
printf "<?php\nclass Tag extends Model {}\n" > "$MP/app/Models/Tag.php"
contains "$(CLAUDE_PROJECT_DIR="$MP" bash "$H/repo-map.sh")" "- Tag" "map regenerates when files change"
CX="$TMP/cx"; gproj "$CX"; export CLAUDE_PROJECT_DIR="$CX"; bash "$H/tasks.sh" init >/dev/null
printf -- '---\nid: 001\ntitle: Base\nstatus: todo\n---\n' > "$CX/.claude/tasks/001-a.md"
printf -- '---\nid: 002\ntitle: Next\nstatus: todo\ndepends: 001\n---\n' > "$CX/.claude/tasks/002-b.md"
bash "$H/tasks.sh" start 001 >/dev/null; printf '<?php // svc\n' > "$CX/app/Svc.php"; bash "$H/tasks.sh" close 001 "added Svc" >/dev/null
O="$(bash "$H/tasks.sh" context 002)"
contains "$O" "added Svc" "context includes the dependency's log line"
contains "$O" "app/Svc.php" "context includes the files the dependency changed"
unset CLAUDE_PROJECT_DIR
O="$(printf '{"agent_type":"laravel-data-layer"}' | CLAUDE_PROJECT_DIR="$P" bash "$H/subagent-context.sh")"
contains "$O" '"hookEventName": "SubagentStart"' "subagents get the context as SubagentStart"
contains "$O" "tasks.sh map" "subagents are told to use the map"
SET="$(cat "$KIT/.claude/settings.json")"
contains "$SET" "compact" "context is re-injected after compaction"
contains "$SET" '^(laravel-.*|blade-.*)$' "SubagentStart is scoped to kit agents"
L1="$(CLAUDE_PROJECT_DIR="$P" bash "$H/session-context.sh" | jq -r .hookSpecificOutput.additionalContext | wc -c)"
[ "$L1" -lt 9000 ] && ok "session context stays under the 10,000-char hook cap ($L1)" || bad "session context over the hook cap ($L1)"

section "owner steps: verdict gate, review/accept, no push"
V="$TMP/gate"; gproj "$V"
CLAUDE_PROJECT_DIR="$V" bash "$H/tasks.sh" init >/dev/null 2>&1
mkt() { printf -- '---\nid: %s\ntitle: %s\nstatus: %s\ndepends: %s\n---\n\n## Acceptance\n- [ ] %s\n\n## Log\n' "$1" "$2" "$3" "${5:-}" "$4" > "$V/.claude/tasks/$1-t.md"; }
gt() { CLAUDE_PROJECT_DIR="$V" LARAVEL_WF_REQUIRE_VERDICT=on bash "$H/tasks.sh" "$@" 2>&1; }
mkt 101 First draft "[browser] it shows"
mkt 102 Second todo "[browser] it shows" 101
contains "$(CLAUDECODE=1 gt approve 101)" "user's step" "approve refuses inside Claude Code"
contains "$(gt show 101)" "status: draft" "the draft stays a draft"
gt approve 101 >/dev/null; contains "$(gt show 101)" "status: todo" "approve works from the user's terminal"
gt start 101 >/dev/null; echo b > "$V/b.txt"
contains "$(gt close 101 built)" "no verdict recorded" "close refuses without a verdict"
contains "$(gt show 101)" "status: doing" "and the task is still doing"
gt verdict 101 FAIL 1 >/dev/null
contains "$(gt close 101 built)" "FAIL" "close refuses after FAIL"
gt verdict 101 SKIPPED 2 >/dev/null
contains "$(gt close 101 built)" "can-skip-verify" "SKIPPED needs can-skip-verify's yes"
gt verdict 101 UNVERIFIED 2 >/dev/null
contains "$(gt close 101 'built; UNVERIFIED [browser]: it shows')" "tasks.sh accept 101" "close after UNVERIFIED says what the user does"
contains "$(gt show 101)" "status: review" "UNVERIFIED lands in review, not done"
contains "$(gt next)" "no runnable task" "dependents wait for the accept"
contains "$(CLAUDECODE=1 gt accept 101)" "user's step" "accept refuses inside Claude Code"
gt accept 101 >/dev/null; contains "$(gt show 101)" "status: done" "accept moves review to done"
contains "$(gt show 101)" "accepted by the user" "and logs it"
contains "$(gt next)" "102-t.md" "then the dependent runs"
gt start 102 >/dev/null; gt verdict 102 PASS 1 >/dev/null; gt close 102 "built it" >/dev/null
contains "$(gt show 102)" "status: done" "PASS closes to done"
mkt 103 Third todo "[review] it reads well"
gt start 103 >/dev/null; echo c >> "$V/composer.json"
gt can-skip-verify 103 >/dev/null; gt verdict 103 SKIPPED 1 >/dev/null; gt close 103 tiny >/dev/null
contains "$(gt show 103)" "status: done" "an allowed SKIPPED closes"
mkt 104 Fourth review '[browser] x'
contains "$(CLAUDE_PROJECT_DIR="$V" bash "$H/session-context.sh")" "awaiting the user's check" "the session report counts review tasks"
own() { printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$H/guard-owner.sh" >/dev/null 2>&1; echo $?; }
for c in 'git push' 'git push origin main' 'cd app && git -C .. push -u origin x' '"git" push' '/usr/bin/git push' 'git -c a=b push' 'gh pr create --fill' 'gh pr merge 3' \
         'bash .claude/hooks/tasks.sh approve all' 'bash $T approve 001' 'bash ~/.claude/hooks/tasks.sh accept 001' \
         "sed -i 's/status: draft/status: todo/' .claude/tasks/001-x.md" 'echo status: todo > .claude/tasks/001-x.md' \
         'sudo -u x git push' 'timeout 30 git push' 'sh -c "git push"' "$(printf "bash <<'EOF'\ngit push\nEOF")" \
         "$(printf "cat <<EOF > f\nx\nEOF\ngit push")"; do
  check "owner guard blocks: $c" "$(own "$c")" "2"
done
for c in 'git status' 'git commit -m "push the fix"' 'echo push' 'gh pr view' 'git log --oneline | head' \
         'git commit -m "run tasks.sh approve, then git push"' 'echo tasks.sh approve' \
         "$(printf "python3 - <<'PY'\ntasks.sh accept 1\ngit push\nPY")" \
         'bash .claude/hooks/tasks.sh close 001 "approve flow"' 'grep -n status: .claude/tasks/001-x.md' \
         "$(printf "bash .claude/hooks/tasks.sh new 005-x <<'TASK'\n---\nstatus: draft\n---\nsee .claude/tasks/ > x\nTASK")"; do
  check "owner guard allows: ${c%%$'\n'*}" "$(own "$c")" "0"
done
check "LARAVEL_WF_ALLOW_PUSH=1 still sends plain git push through git-sync" "$(LARAVEL_WF_ALLOW_PUSH=1 own 'git push')" "2"
check "LARAVEL_WF_ALLOW_PUSH=1 allows git-sync.sh push" "$(LARAVEL_WF_ALLOW_PUSH=1 own 'bash .claude/hooks/git-sync.sh push')" "0"
contains "$(cat "$KIT/.claude/settings.json")" "guard-owner.sh" "the owner guard is registered before Bash runs"
contains "$(cat "$KIT/install.sh")" "guard-owner" "the installer knows the owner guard"

section "plugin packaging (2.4)"
PJ="$KIT/.claude-plugin/plugin.json"; MJ="$KIT/.claude-plugin/marketplace.json"
jq -e . "$PJ" >/dev/null 2>&1 && ok "plugin.json is valid JSON" || bad "plugin.json is valid JSON"
jq -e . "$MJ" >/dev/null 2>&1 && ok "marketplace.json is valid JSON" || bad "marketplace.json is valid JSON"
check "plugin version matches VERSION" "$(jq -r .version "$PJ")" "$(cat "$KIT/VERSION")"
check "plugin is named laravel (commands stay /laravel:*)" "$(jq -r .name "$PJ")" "laravel"
check "marketplace lists the same plugin" "$(jq -r '.plugins[0].name' "$MJ")" "laravel"
check "plugin.json lists every agent" "$(jq -r '.agents[]' "$PJ" | sed 's|^\./||' | sort | tr '\n' ' ')" "$(cd "$KIT" && ls .claude/agents/*.md | sort | tr '\n' ' ')"
for f in $(jq -r '.agents[], .commands, .skills' "$PJ"); do [ -e "$KIT/$f" ] && ok "plugin path exists: $f" || bad "plugin path exists: $f"; done
check "hooks.json is up to date with settings.json (jq -f hooks/build-hooks.jq)" \
  "$(jq -f "$KIT/hooks/build-hooks.jq" "$KIT/.claude/settings.json" | jq -S .)" "$(jq -S . "$KIT/hooks/hooks.json")"
for n in $(jq -r '.. | .command? // empty' "$KIT/hooks/hooks.json" | awk '{print $NF}'); do
  [ -x "$KIT/.claude/hooks/$n.sh" ] && ok "plugin hook exists: $n" || bad "plugin hook exists: $n"
done
check "plugin SubagentStart matches scoped agent names" "$(jq -r '.hooks.SubagentStart[0].matcher' "$KIT/hooks/hooks.json")" "(^|:)(laravel|blade)-"
for a in laravel-verifier laravel:laravel-verifier laravel:blade-ui-builder; do
  [[ "$a" =~ $(jq -r '.hooks.SubagentStart[0].matcher' "$KIT/hooks/hooks.json") ]] && ok "subagent matcher takes $a" || bad "subagent matcher takes $a"
done
[[ "general-purpose" =~ $(jq -r '.hooks.SubagentStart[0].matcher' "$KIT/hooks/hooks.json") ]] && bad "subagent matcher skips other agents" || ok "subagent matcher skips other agents"

PL="$TMP/plugin-proj"; cp -R "$P" "$PL"; rm -rf "$PL/.claude"; mkdir -p "$PL/.claude"
pd() { CLAUDE_PLUGIN_ROOT="$KIT" CLAUDE_PROJECT_DIR="$PL" bash "$H/plugin-dispatch.sh" "$@"; }
contains "$(pd session-context </dev/null)" "Kit helpers: \`$H\`" "plugin session report names the plugin's helper folder"
contains "$(pd session-context </dev/null)" "laravel-workflow $(cat "$KIT/VERSION")" "plugin session report reads the kit VERSION"
check "dispatcher refuses odd hook names" "$(pd '../x' </dev/null; echo $?)" "0"
mkdir -p "$PL/.claude/hooks"; cp "$H/session-context.sh" "$PL/.claude/hooks/"
lacks "$(pd session-context </dev/null)" "installed twice" "a stray project file alone doesn't make the plugin step aside"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/session-context.sh"}]}]}}' > "$PL/.claude/settings.json"
contains "$(pd session-context </dev/null)" "installed twice" "with a registered project install, the plugin steps aside and says so"
printf '#!/bin/sh\nexit 0\n' > "$PL/.claude/hooks/guard-read.sh"
printf '{"hooks":{"PreToolUse":[{"matcher":"Read","hooks":[{"type":"command","command":"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-read.sh"}]}]}}' > "$PL/.claude/settings.local.json"
check "a project file can't switch a plugin guard off" "$(printf '{"tool_input":{"file_path":"%s/.env"}}' "$PL" | pd guard-read >/dev/null 2>&1; echo $?)" "2"
rm -rf "$PL/.claude/hooks" "$PL/.claude/settings.json" "$PL/.claude/settings.local.json"
check "without a project install the plugin's guard blocks" "$(printf '{"tool_input":{"file_path":"%s/.env"}}' "$PL" | pd guard-read >/dev/null 2>&1; echo $?)" "2"

rd() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | CLAUDE_PROJECT_DIR="$PL" bash "$H/guard-read.sh" >/dev/null 2>&1; echo $?; }
for f in "$PL/.env" "$PL/.env.testing" "$PL/.env.production" "$PL/auth.json" "$PL/storage/oauth-private.key" \
         "$PL/storage/logs/laravel.log" "$PL/certs/server.pem" "$HOME/.ssh/id_ed25519" "$HOME/.config/composer/auth.json"; do
  check "guard-read blocks ${f#"$PL"/}" "$(rd "$f")" "2"
done
for f in "$PL/.env.example" "$PL/app/Models/User.php" "$PL/config/app.php" "$PL/resources/views/storage.blade.php"; do
  check "guard-read allows ${f#"$PL"/}" "$(rd "$f")" "0"
done
check "LARAVEL_WF_SECRETS_GUARD=off turns guard-read off" "$(LARAVEL_WF_SECRETS_GUARD=off rd "$PL/.env")" "0"

eval "$(CLAUDE_PROJECT_DIR="$PL" bash "$H/stack.sh" | grep '^CMD_TEST=')"
ah() { printf '{"tool_name":"Bash","tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -Rs .)" | CLAUDE_PROJECT_DIR="$PL" bash "$H/allow-helpers.sh" | grep -q '"allow"' && echo allow || echo prompt; }
amcp() { printf '{"tool_name":"%s","tool_input":{}}' "$1" | CLAUDE_PROJECT_DIR="$PL" bash "$H/allow-helpers.sh" | grep -q '"allow"' && echo allow || echo prompt; }
for c in "bash $H/tasks.sh list" "bash $H/tasks.sh close 001 \"built it, kept the API\"" "bash $H/repo-map.sh" "bash $H/stack.sh" \
         "$CMD_TEST" "$CMD_TEST tests/Feature/PostTest.php" "php -l app/Models/Post.php" "php artisan route:list" "printenv LARAVEL_WF_DEV_URL" \
         "$(printf "bash $H/tasks.sh new 004-add-footer <<'TASK'\n---\nid: 004\n---\nTASK")"; do
  check "allow-helpers approves: ${c%%$'\n'*}" "$(ah "$c")" "allow"
done
for c in "bash $H/tasks.sh list; rm -rf x" "bash $H/tasks.sh close 001 \"\$(id)\"" "bash $H/tasks.sh log 001 \`id\`" \
         "bash ${H/.claude/xclaude}/tasks.sh list" "bash .claude/hooks/tasks.sh next" "bash $H/verify.sh --baseline" "bash $H/run-tasks.sh" \
         "$CMD_TEST && curl x" "$CMD_TEST --configuration=evil.xml" "$CMD_TEST -c x" "php -l -d auto_prepend_file=x.php a.php" \
         "php artisan tinker" "php artisan migrate" "bash $H/tasks.sh list > out.txt" \
         "$(printf "bash $H/tasks.sh new 004-add-footer <<'TASK'\nTASK\nrm -rf x\nTASK")" \
         "$(printf "bash $H/tasks.sh new 004-add-footer <<TASK\nx\nTASK")"; do
  check "allow-helpers leaves to the prompt: ${c%%$'\n'*}" "$(ah "$c")" "prompt"
done
check "allow-helpers approves Boost search-docs" "$(amcp mcp__laravel-boost__search-docs)" "allow"
check "allow-helpers approves Boost database-schema" "$(amcp mcp__laravel-boost__database-schema)" "allow"
check "allow-helpers leaves other Boost tools to the prompt" "$(amcp mcp__laravel-boost__tinker)" "prompt"
check "allow-helpers leaves other MCP servers to the prompt" "$(amcp mcp__other__search-docs)" "prompt"
check "owner guard blocks verify.sh --baseline (plugins have no deny rule)" "$(own "bash $H/verify.sh --baseline")" "2"
check "owner guard allows plain verify.sh" "$(own "bash $H/verify.sh")" "0"
contains "$(printf '{"tool_input":{"command":"bash x/tasks.sh approve 001"}}' | CLAUDE_PROJECT_DIR="$PL" bash "$H/guard-owner.sh" 2>&1)" "bash $H/tasks.sh approve" "owner guard names the helper folder actually in use"

DRAFT="$(printf "bash $KIT/.claude/hooks/tasks.sh new 004-x <<'TASK'\n---\nid: 004\n---\nRead config, never .env\nTASK")"
check "guard-secrets: plugin tasks.sh new heredoc passes" "$(CLAUDE_PLUGIN_ROOT="$KIT" sec "$DRAFT")" "0"
check "guard-secrets: the same heredoc outside a plugin is still checked" "$(sec "$DRAFT")" "2"
O="$(printf '{"tool_input":{"command":"cat .e*"}}' | (cd "$KIT" && CLAUDE_PROJECT_DIR="$KIT" bash "$H/guard-secrets.sh") 2>&1)"
contains "$O" "(.e*)" "secrets message shows the pattern"
lacks "$O" "CHANGELOG.md" "and doesn't glob-expand it into the folder's files"
lacks "$(cat "$KIT"/.claude/agents/*.md "$KIT"/.claude/commands/laravel/*.md)" "bash .claude/hooks/" "prompts don't hard-code the project helper path"
contains "$(cat "$KIT/install.sh")" "plugin-dispatch" "the uninstaller removes the plugin-only hooks"

section "no comments: pure code (2.4)"
CG="$TMP/comments"; mkdir -p "$CG/app" "$CG/resources/views"
gc() { jq -n --arg f "$1" --arg o "$2" --arg n "$3" '{tool_name:"Edit",tool_input:{file_path:$f,old_string:$o,new_string:$n}}' | CLAUDE_PROJECT_DIR="$CG" bash "$H/guard-comments.sh" >/dev/null 2>&1; echo $?; }
check "blocks a PHP line comment" "$(gc "$CG/app/A.php" x "// load users${NL}\$u = User::all();")" "2"
check "blocks a trailing PHP comment" "$(gc "$CG/app/A.php" x "\$u = User::all(); // all of them")" "2"
check "blocks a # comment" "$(gc "$CG/app/A.php" x "# note${NL}\$a = 1;")" "2"
check "blocks a prose docblock" "$(gc "$CG/app/A.php" x "/**${NL} * Get the posts.${NL} */")" "2"
check "blocks a Blade comment" "$(gc "$CG/resources/views/a.blade.php" x "{{-- header --}}${NL}<h1>Hi</h1>")" "2"
check "blocks an HTML comment in Blade" "$(gc "$CG/resources/views/a.blade.php" x "<!-- nav -->")" "2"
check "blocks a JS comment" "$(gc "$CG/resources/js/app.js" x "const a = foo(); // why")" "2"
check "blocks a CSS comment" "$(gc "$CG/resources/css/app.css" x "/* brand */${NL}a { color: red; }")" "2"
check "allows a PHP attribute" "$(gc "$CG/app/A.php" x "#[Override]${NL}public function x(): void {}")" "0"
check "allows type-only docblock tags" "$(gc "$CG/app/A.php" x "/**${NL} * @param array<int, string> \$ids${NL} * @return HasMany<Post, \$this>${NL} */")" "0"
check "allows @phpstan-ignore" "$(gc "$CG/app/A.php" x "\$a = foo(); // @phpstan-ignore-line")" "0"
check "allows a URL in a string" "$(gc "$CG/app/A.php" x "\$u = 'https://example.com';")" "0"
check "allows a CSS universal selector" "$(gc "$CG/resources/css/app.css" x "* { box-sizing: border-box; }")" "0"
check "ignores markdown" "$(gc "$CG/README.md" x "<!-- hi -->")" "0"
check "ignores vendor/" "$(gc "$CG/vendor/x/A.php" x "// hi")" "0"
printf '<?php\n// existing note\n$a = 1;\n' > "$CG/app/B.php"
check "comments already in the file are kept" "$(gc "$CG/app/B.php" '$a = 1;' "// existing note${NL}\$a = 2;")" "0"
check "LARAVEL_WF_COMMENT_GUARD=off turns it off" "$(LARAVEL_WF_COMMENT_GUARD=off gc "$CG/app/A.php" x "// hi")" "0"
printf '<?php\nclass C {}\n' > "$CG/app/C.php"
O="$(jq -n --arg f "$CG/app/C.php" --arg c "<?php${NL}// make it${NL}class C {}" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}' | CLAUDE_PROJECT_DIR="$CG" bash "$H/guard-comments.sh" 2>&1)"
contains "$O" "// make it" "a Write that adds a comment is blocked and names the line"
contains "$(cat "$KIT/.claude/settings.json")" "guard-comments.sh" "the comment guard runs before Edit/Write"
for f in laravel-route-builder laravel-data-layer blade-ui-builder laravel-test-writer; do
  contains "$(cat "$KIT/.claude/agents/$f.md")" "No comments — pure code" "$f is told: no comments"
done
contains "$(cat "$KIT/.claude/commands/laravel/task.md")" "No comments — pure code" "the task runner is told: no comments"
contains "$(cat "$KIT/.claude/skills/php-conventions/SKILL.md")" "carries no comments" "php-conventions states the rule"
contains "$(CLAUDE_PROJECT_DIR="$P" bash "$H/session-context.sh")" "carries no comments" "the session report states the rule"

section "git: commit, pull the stage branch, push (2.4)"
GS="$TMP/gitsync"; mkdir -p "$GS"
git init -q --bare "$GS/remote.git"
git clone -q "$GS/remote.git" "$GS/app" 2>/dev/null
gcfg() { git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; }
gcfg "$GS/app"
( cd "$GS/app" && git checkout -q -b main && printf 'a\n' > a.txt && git add a.txt && git commit -qm init && git push -q origin main \
  && git checkout -q -b stage && git push -q origin stage && git checkout -q -b feature && printf 'f\n' > f.txt && git add f.txt && git commit -qm feature ) 2>/dev/null
git clone -q "$GS/remote.git" "$GS/mate" 2>/dev/null; gcfg "$GS/mate"
( cd "$GS/mate" && git checkout -q stage && printf 's\n' > s.txt && git add s.txt && git commit -qm "stage work" && git push -q origin stage ) 2>/dev/null
gsync() { (cd "$GS/app" && CLAUDE_PROJECT_DIR="$GS/app" bash "$H/git-sync.sh" "$@" 2>&1); }
gsync_rc() { (cd "$GS/app" && CLAUDE_PROJECT_DIR="$GS/app" bash "$H/git-sync.sh" "$@" >/dev/null 2>&1); echo $?; }
check "no stage branch configured: exit 2" "$(gsync_rc push)" "2"
contains "$(gsync stage)" "likely candidates on origin: stage" "it suggests the stage branch from the remote"
contains "$(gsync stage stage)" "stage branch: stage" "stage <branch> records it"
contains "$(cat "$GS/app/.claude/workflow.conf")" "STAGE_BRANCH=stage" "the choice lives in .claude/workflow.conf"
check "LARAVEL_WF_STAGE_BRANCH overrides the file" "$(cd "$GS/app" && LARAVEL_WF_STAGE_BRANCH=main CLAUDE_PROJECT_DIR="$GS/app" bash "$H/git-sync.sh" stage)" "main"
check "an invalid branch name is refused" "$(gsync_rc stage 'bad..name')" "1"
( cd "$GS/app" && git add .claude/workflow.conf && git commit -qm conf )
check "push refuses a branch missing the stage branch's commits" "$(gsync_rc push)" "5"
contains "$(gsync sync)" "brought in" "sync merges the stage branch in"
[ -f "$GS/app/s.txt" ] && ok "the stage branch's file arrived" || bad "the stage branch's file arrived"
check "after sync, push succeeds" "$(gsync_rc push)" "0"
git -C "$GS/remote.git" rev-parse --verify --quiet refs/heads/feature >/dev/null && ok "the branch is on the remote" || bad "the branch is on the remote"
printf 'dirty\n' > "$GS/app/dirty.txt"
check "sync refuses uncommitted changes" "$(gsync_rc sync)" "4"
check "push refuses uncommitted changes" "$(gsync_rc push)" "4"
rm -f "$GS/app/dirty.txt"
( cd "$GS/mate" && git pull -q origin stage && printf 'mate\n' > a.txt && git commit -qam "mate edit" && git push -q origin stage ) 2>/dev/null
( cd "$GS/app" && printf 'mine\n' > a.txt && git commit -qam "my edit" )
check "a conflicting stage change: exit 3" "$(gsync_rc sync)" "3"
contains "$(cd "$GS/app" && git diff --name-only --diff-filter=U)" "a.txt" "the conflict is left for resolving"
check "sync refuses while a merge is in progress" "$(gsync_rc sync)" "6"
( cd "$GS/app" && git merge --abort )
printf 'K=1\n' > "$GS/app/.env"; ( cd "$GS/app" && git add -f .env )
check "check-staged refuses a staged .env" "$(gsync_rc check-staged)" "1"
( cd "$GS/app" && git restore --staged .env && rm .env )
check "check-staged passes without secrets" "$(gsync_rc check-staged)" "0"
contains "$(gsync status)" "stage: origin/stage" "status names the stage branch"

CF="$GS/app/.claude/.cache/push-consent"
pc() { jq -n --arg p "$1" '{prompt:$p, session_id:"s1"}' | CLAUDE_PROJECT_DIR="$GS/app" bash "$H/push-consent.sh"; [ -f "$CF" ] && echo yes || echo no; rm -f "$CF"; }
check "/laravel:sync records the user's consent" "$(pc '/laravel:sync fix login')" "yes"
check "a plain request doesn't" "$(pc 'please push it')" "no"
check "a later mention doesn't" "$(pc 'then run /laravel:sync')" "no"
check "a different /sync command doesn't" "$(pc '/sync')" "no"
ownp() { jq -n --arg c "$1" --arg s "${2:-s1}" '{session_id:$s, tool_input:{command:$c}}' | CLAUDE_PROJECT_DIR="$GS/app" bash "$H/guard-owner.sh" >/dev/null 2>&1; echo $?; }
check "git-sync.sh push without consent is blocked" "$(ownp "bash $H/git-sync.sh push")" "2"
mkdir -p "$GS/app/.claude/.cache"; printf '%s s1\n' "$(date +%s)" > "$CF"
check "with fresh consent it runs" "$(ownp "bash $H/git-sync.sh push")" "0"
check "a variable holding the helper counts too" "$(ownp 'G=x; bash $G push')" "0"
check "plain git push stays blocked even with consent" "$(ownp 'git push origin feature')" "2"
check "consent from another session doesn't count" "$(ownp "bash $H/git-sync.sh push" s2)" "2"
printf '%s\n' "$(date +%s)" > "$CF"
check "consent without a session doesn't count" "$(ownp "bash $H/git-sync.sh push")" "2"
printf '%s s1\n' "$(( $(date +%s) + 100000 ))" > "$CF"
check "a timestamp in the future doesn't count" "$(ownp "bash $H/git-sync.sh push")" "2"
printf '%s s1\n' "$(( $(date +%s) - 4000 ))" > "$CF"
check "stale consent (over 30 min) is blocked" "$(ownp "bash $H/git-sync.sh push")" "2"
check "Claude can't write the consent itself" "$(ownp 'date +%s > .claude/.cache/push-consent')" "2"
check "not from inside the cache folder either" "$(ownp 'cd .claude/.cache && date +%s > push-consent')" "2"
check "reading the hook script by name is fine" "$(ownp 'cat .claude/hooks/push-consent.sh')" "0"
check "a mixed-quote heredoc delimiter can't hide a push" "$(ownp "$(printf 'cat <<"E"OF > f\nx\nEOF\ngit push')")" "2"
check "a heredoc with no terminator is scanned whole" "$(ownp "$(printf 'cat <<EOF > f\nx\ngit push')")" "2"
check "a tab-indented terminator only ends <<-" "$(ownp "$(printf 'cat <<EOF > f\n\tEOF\ngit push\nEOF')")" "0"
check "a quoted-delimiter task draft still passes" "$(ownp "$(printf "bash .claude/hooks/tasks.sh new 005-x <<'TASK'\ngit push\nTASK")")" "0"
mkdir -p "$GS/app/.claude/.cache"; printf 'CMD_TEST="rm -rf x"\n' > "$GS/app/.claude/.cache/stack.env"
check "allow-helpers ignores a tampered stack cache" "$(printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf x"}}' | CLAUDE_PROJECT_DIR="$GS/app" bash "$H/allow-helpers.sh" | grep -c allow)" "0"
check "allow-helpers still approves a known verify command" "$(printf '{"tool_name":"Bash","tool_input":{"command":"php artisan test tests/Feature/A.php"}}' | CLAUDE_PROJECT_DIR="$GS/app" bash "$H/allow-helpers.sh" | grep -c allow)" "1"
rm -f "$GS/app/.claude/.cache/stack.env"
check "sync and status need no consent" "$(ownp "bash $H/git-sync.sh sync")$(ownp "bash $H/git-sync.sh status")" "00"
contains "$(cat "$KIT/.claude/commands/laravel/sync.md")" "disable-model-invocation: true" "/laravel:sync runs only when the user types it"
contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$KIT/.claude/settings.json")" "push-consent.sh" "the consent hook is registered"
IG="$TMP/install-stage"; lproj "$IG"; git init -q "$IG"
bash "$KIT/install.sh" "$IG" --stage-branch develop >/dev/null 2>&1
contains "$(cat "$IG/.claude/workflow.conf" 2>/dev/null)" "STAGE_BRANCH=develop" "install.sh --stage-branch records the stage branch"
contains "$(CLAUDE_PROJECT_DIR="$IG" bash "$H/session-context.sh")" "stage branch \`develop\`" "the session report names the stage branch"

# ---------------------------------------------------------------- summary -----
printf '\n%s\n' "-----------------------------------------"
if [ "$FAIL" -eq 0 ]; then
  printf 'All %d assertions passed.\n' "$PASS"; exit 0
else
  printf '%d passed, %d FAILED:\n' "$PASS" "$FAIL"
  printf '  - %s\n' "${FAILED[@]}"; exit 1
fi
