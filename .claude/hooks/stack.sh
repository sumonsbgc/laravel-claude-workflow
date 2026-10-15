#!/usr/bin/env bash
# Shared stack detection for the Laravel agentic workflow.
# Usage:  eval "$("$CLAUDE_PROJECT_DIR/.claude/hooks/stack.sh")"
# Emits KEY="value" lines. Never fails: unknown values come back empty.
set -uo pipefail

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
COMPOSER="$ROOT/composer.json"
LOCK="$ROOT/composer.lock"
PKG="$ROOT/package.json"

# Cache: detection costs ~25 subprocesses and only changes when a manifest or the
# installed tree does. LARAVEL_WF_NO_CACHE=1 forces a fresh probe.
CACHE="$ROOT/.claude/.cache/stack.env"
# frontend-design is a user- or project-level skill. It depends on $HOME, which is not part
# of the cache key, and costs one -d test — so it is computed fresh on every call, never cached.
design_skill() {
  local d
  for d in "$ROOT/.claude/skills/frontend-design" "$HOME/.claude/skills/frontend-design"; do
    [ -d "$d" ] && { printf 'DESIGN_SKILL="yes"\n'; return; }
  done
  printf 'DESIGN_SKILL=""\n'
}

# Every consumer `eval`s this output, and values come from composer.json/.env — repo content,
# not ours. Reduce each value to a charset that cannot carry shell syntax ($, `, ", \, ;, newline).
safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9 ._~^<>=|@/:+,*-'; }
# A cache line is trusted only if it has exactly the shape this script writes.
cache_ok() { ! grep -qvE '^[A-Z_]+="[A-Za-z0-9 ._~^<>=|@/:+,*-]*"$' "$1"; }

if [ "${LARAVEL_WF_NO_CACHE:-0}" != 1 ] && [ -f "$CACHE" ] && [ -f "$COMPOSER" ] && cache_ok "$CACHE" &&
   [ "$CACHE" -nt "$COMPOSER" ] &&
   { [ ! -f "$LOCK" ] || [ "$CACHE" -nt "$LOCK" ]; } &&
   { [ ! -f "$PKG" ]  || [ "$CACHE" -nt "$PKG" ]; } &&
   { [ ! -d "$ROOT/vendor" ] || [ "$CACHE" -nt "$ROOT/vendor" ]; }; then
  cat "$CACHE"; design_skill; exit 0
fi

dep() { # dep <name> -> declared version constraint, or empty
  [ -f "$COMPOSER" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg d "$1" '((.require//{}) + (."require-dev"//{}))[$d] // ""' "$COMPOSER" 2>/dev/null
  else
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$COMPOSER" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/'
  fi
}
locked() { # locked <name> -> installed version from composer.lock
  [ -f "$LOCK" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg d "$1" '[(.packages//[]),(."packages-dev"//[])] | flatten | map(select(.name==$d)) | .[0].version // ""' "$LOCK" 2>/dev/null
  else
    grep -A2 "\"name\": \"$1\"" "$LOCK" 2>/dev/null | grep -m1 '"version"' | sed -E 's/.*"version": "([^"]+)".*/\1/'
  fi
}
npm_dep() { # npm_dep <name> -> declared range from package.json
  [ -f "$PKG" ] || return 0
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg d "$1" '((.dependencies//{}) + (.devDependencies//{}))[$d] // ""' "$PKG" 2>/dev/null
  else
    grep -oE "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]+\"" "$PKG" 2>/dev/null | head -1 | sed -E 's/.*:[[:space:]]*"([^"]+)"/\1/'
  fi
}
composer_script() { # composer_script <name> -> 0 if defined
  [ -f "$COMPOSER" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    [ "$(jq -r --arg s "$1" '.scripts[$s] // "" | tostring' "$COMPOSER" 2>/dev/null)" != "" ]
  else
    grep -qE "\"$1\"[[:space:]]*:" "$COMPOSER" 2>/dev/null
  fi
}
npm_script() {
  [ -f "$PKG" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    [ "$(jq -r --arg s "$1" '.scripts[$s] // ""' "$PKG" 2>/dev/null)" != "" ]
  else
    grep -qE "\"$1\"[[:space:]]*:" "$PKG" 2>/dev/null
  fi
}
env_key() { # env_key <KEY> -> value from .env, or from .env.example, or empty.
  # Only ever called with non-secret driver keys (see below) — never credentials.
  local k="$1" f v
  for f in "$ROOT/.env" "$ROOT/.env.example"; do
    [ -f "$f" ] || continue
    v="$(grep -m1 -E "^[[:space:]]*$k=" "$f" 2>/dev/null | sed -E "s/^[[:space:]]*$k=//" | tr -d '"'"'"' \r')"
    [ -n "$v" ] && { printf '%s' "$v"; return; }
  done
}

LARAVEL_V="$(locked laravel/framework)"
[ -n "$LARAVEL_V" ] || LARAVEL_V="$(dep laravel/framework)"
# Major version drives which version-specific reference applies (references/laravel13.md).
LARAVEL_MAJOR="$(printf '%s' "$LARAVEL_V" | grep -oE '[0-9]+' | head -1)"
# Laravel Boost: first-party MCP server with version-matched docs search.
BOOST="$(locked laravel/boost)"; [ -n "$BOOST" ] || BOOST="$(dep laravel/boost)"
# Laravel 13 default: cache.serializable_classes => false (objects in the cache don't come back).
CACHE_SERIALIZABLE=""
grep -qE "'serializable_classes'[[:space:]]*=>[[:space:]]*false" "$ROOT/config/cache.php" 2>/dev/null && CACHE_SERIALIZABLE="false"
PHP_V="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION.".".PHP_RELEASE_VERSION;' 2>/dev/null || true)"
PHP_REQUIRED="$(dep php)"

# Test runner
TEST_RUNNER=""
[ -n "$(dep pestphp/pest)" ] && TEST_RUNNER="pest"
[ -z "$TEST_RUNNER" ] && [ -f "$ROOT/phpunit.xml" ] && TEST_RUNNER="phpunit"
TEST_VERSION="$(locked pestphp/pest)"

# Quality tooling
PINT=""; [ -x "$ROOT/vendor/bin/pint" ] && PINT="yes"
[ -z "$PINT" ] && [ -n "$(dep laravel/pint)" ] && PINT="declared"
STATIC=""
[ -x "$ROOT/vendor/bin/phpstan" ] && STATIC="phpstan"
[ -n "$(dep larastan/larastan)$(dep nunomaduro/larastan)" ] && STATIC="larastan"
[ -x "$ROOT/vendor/bin/psalm" ] && STATIC="${STATIC:+$STATIC+}psalm"
STATIC_CONFIG=""
for c in phpstan.neon phpstan.neon.dist phpstan.dist.neon psalm.xml; do
  [ -f "$ROOT/$c" ] && STATIC_CONFIG="$c" && break
done

# View layer
VIEW="blade"
[ -n "$(dep livewire/livewire)" ] && VIEW="blade+livewire"
[ -n "$(dep inertiajs/inertia-laravel)" ] && VIEW="inertia"
[ -n "$(dep laravel/folio)" ] && VIEW="${VIEW}+folio"
ALPINE="$(npm_dep alpinejs)"
LIVEWIRE_V="$(locked livewire/livewire)"

# Assets
TW_V="$(npm_dep tailwindcss)"
TW_INSTALLED="$(node -p 'require(process.argv[1]).version' "$ROOT/node_modules/tailwindcss/package.json" 2>/dev/null || true)"
BOOTSTRAP_CSS="$(npm_dep bootstrap)"
VITE=""; [ -f "$ROOT/vite.config.js" ] && VITE="vite.config.js"
[ -f "$ROOT/vite.config.ts" ] && VITE="vite.config.ts"
[ -z "$VITE" ] && [ -f "$ROOT/webpack.mix.js" ] && VITE="mix"

# Auth / permission packages worth knowing about before hand-rolling one
AUTH=""
[ -n "$(dep laravel/breeze)" ]    && AUTH="breeze"
[ -n "$(dep laravel/jetstream)" ] && AUTH="jetstream"
[ -n "$(dep laravel/fortify)" ]   && AUTH="${AUTH:+$AUTH+}fortify"
[ -n "$(dep laravel/sanctum)" ]   && AUTH="${AUTH:+$AUTH+}sanctum"
PERMISSIONS=""
[ -n "$(dep spatie/laravel-permission)" ] && PERMISSIONS="spatie/laravel-permission"

# Admin panel packages
PANEL=""
[ -n "$(dep filament/filament)" ] && PANEL="filament"
[ -n "$(dep laravel/nova)" ] && PANEL="nova"

# Runtime drivers. Only non-secret driver keys are read out of .env.
DB_CONN="$(env_key DB_CONNECTION)"
CACHE_STORE="$(env_key CACHE_STORE)"; [ -n "$CACHE_STORE" ] || CACHE_STORE="$(env_key CACHE_DRIVER)"
QUEUE_CONN="$(env_key QUEUE_CONNECTION)"
SESSION_DRIVER="$(env_key SESSION_DRIVER)"

# Redis, storage, CDN and images. Only non-secret keys are read; AWS_URL is reported as set/unset.
REDIS_CLIENT="$(env_key REDIS_CLIENT)"
[ -z "$REDIS_CLIENT" ] && [ -n "$(dep predis/predis)" ] && REDIS_CLIENT="predis?"
PHP_EXT="$(php -m 2>/dev/null | grep -ixE 'redis|gd|imagick' | tr 'A-Z' 'a-z' | sort | tr '\n' ',' | sed 's/,$//')"
FS_DISK="$(env_key FILESYSTEM_DISK)"
S3_ADAPTER=""; [ -n "$(dep league/flysystem-aws-s3-v3)" ] && S3_ADAPTER="yes"
CDN_URL=""; [ -n "$(env_key AWS_URL)" ] && CDN_URL="set"
IMAGES=""
[ -n "$(dep intervention/image)" ] && IMAGES="intervention/image (core Image API)"
[ -n "$(dep intervention/image-laravel)" ] && IMAGES="intervention/image-laravel"
[ -n "$(dep spatie/laravel-medialibrary)" ] && IMAGES="${IMAGES:+$IMAGES+}spatie/laravel-medialibrary"
# Rich-text editor in use. Post/Page modules must use the block editor (kit rule).
RICH_EDITOR=""
[ -n "$(npm_dep @wordpress/block-editor)" ] && RICH_EDITOR="gutenberg (@wordpress/block-editor $(npm_dep @wordpress/block-editor))"
for e in ckeditor5 @ckeditor/ckeditor5-build-classic tinymce summernote quill trix; do
  [ -n "$(npm_dep "$e")" ] && RICH_EDITOR="${RICH_EDITOR:+$RICH_EDITOR+}$e"
done
BOOST_MCP=""; grep -qs 'laravel-boost' "$ROOT/.mcp.json" && BOOST_MCP="yes"
AI_RULES=""; [ -f "$ROOT/.ai/rules/index.md" ] && AI_RULES="yes"

# Layout of this particular repo
ROUTE_FILES="$(for f in "$ROOT"/routes/*.php; do [ -f "$f" ] && printf '%s,' "${f##*/}"; done | sed 's/,$//')"
HAS_ACTIONS=""; [ -d "$ROOT/app/Actions" ] && HAS_ACTIONS="app/Actions"
HAS_SERVICES=""; [ -d "$ROOT/app/Services" ] && HAS_SERVICES="app/Services"
HAS_POLICIES=""; [ -d "$ROOT/app/Policies" ] && HAS_POLICIES="app/Policies"
HAS_OBSERVERS=""; [ -d "$ROOT/app/Observers" ] && HAS_OBSERVERS="app/Observers"
HAS_COMPOSERS=""; [ -d "$ROOT/app/View/Composers" ] && HAS_COMPOSERS="app/View/Composers"
HAS_LIVEWIRE=""; [ -d "$ROOT/app/Livewire" ] && HAS_LIVEWIRE="app/Livewire"
[ -z "$HAS_LIVEWIRE" ] && [ -d "$ROOT/app/Http/Livewire" ] && HAS_LIVEWIRE="app/Http/Livewire"

# Preferred verification commands, in order of what the repo actually defines.
PHP_BIN="php"
if composer_script test; then TEST="composer test"
elif [ -n "$TEST_RUNNER" ]; then TEST="$PHP_BIN artisan test"
else TEST=""; fi
if [ "$PINT" = yes ]; then LINT="vendor/bin/pint --test"; FORMAT="vendor/bin/pint"
elif [ "$PINT" = declared ]; then LINT="vendor/bin/pint --test"; FORMAT="vendor/bin/pint"
else LINT=""; FORMAT=""; fi
if [ -x "$ROOT/vendor/bin/phpstan" ]; then ANALYSE="vendor/bin/phpstan analyse"; else ANALYSE=""; fi
if npm_script build; then BUILD="npm run build"; else BUILD=""; fi
if composer_script dev; then DEV="composer dev"
elif npm_script dev; then DEV="npm run dev"
else DEV="$PHP_BIN artisan serve"; fi
MIGRATE="$PHP_BIN artisan migrate"

# Only cache a detection that actually found Laravel. Caching an empty result — php
# missing, a broken jq, a composer install mid-flight — would silently disable the whole
# workflow until composer.json next changed.
if [ -n "$LARAVEL_V" ] && [ "${LARAVEL_WF_NO_CACHE:-0}" != 1 ]; then
  mkdir -p "$(dirname "$CACHE")" 2>/dev/null || true
else
  CACHE="/dev/null"        # failed detection, or an explicit fresh probe: never persist it
fi
{ for kv in \
    "LARAVEL_VERSION=$LARAVEL_V" "LARAVEL_MAJOR=$LARAVEL_MAJOR" "BOOST=$BOOST" "BOOST_MCP=$BOOST_MCP" "AI_RULES=$AI_RULES" "CACHE_SERIALIZABLE=$CACHE_SERIALIZABLE" \
    "RICH_EDITOR=$RICH_EDITOR" "REDIS_CLIENT=$REDIS_CLIENT" "PHP_EXT=$PHP_EXT" "FS_DISK=$FS_DISK" "S3_ADAPTER=$S3_ADAPTER" "CDN_URL=$CDN_URL" "IMAGES=$IMAGES" \
    "PHP_VERSION=$PHP_V" "PHP_REQUIRED=$PHP_REQUIRED" "VIEW_LAYER=$VIEW" "LIVEWIRE_VERSION=$LIVEWIRE_V" \
    "ALPINE_VERSION=$ALPINE" "TAILWIND_VERSION=$TW_V" "TAILWIND_INSTALLED=$TW_INSTALLED" \
    "BOOTSTRAP_VERSION=$BOOTSTRAP_CSS" "ASSET_BUILD=$VITE" "AUTH_STACK=$AUTH" "PERMISSIONS=$PERMISSIONS" \
    "ADMIN_PANEL=$PANEL" "TEST_RUNNER=$TEST_RUNNER" "TEST_VERSION=$TEST_VERSION" "PINT=$PINT" \
    "STATIC_ANALYSIS=$STATIC" "STATIC_CONFIG=$STATIC_CONFIG" "DB_CONNECTION=$DB_CONN" \
    "CACHE_STORE=$CACHE_STORE" "QUEUE_CONNECTION=$QUEUE_CONN" "SESSION_DRIVER=$SESSION_DRIVER" \
    "ROUTE_FILES=$ROUTE_FILES" "DIR_ACTIONS=$HAS_ACTIONS" "DIR_SERVICES=$HAS_SERVICES" \
    "DIR_POLICIES=$HAS_POLICIES" "DIR_OBSERVERS=$HAS_OBSERVERS" "DIR_COMPOSERS=$HAS_COMPOSERS" \
    "DIR_LIVEWIRE=$HAS_LIVEWIRE" "CMD_TEST=$TEST" "CMD_LINT=$LINT" "CMD_FORMAT=$FORMAT" \
    "CMD_ANALYSE=$ANALYSE" "CMD_BUILD=$BUILD" "CMD_DEV=$DEV" "CMD_MIGRATE=$MIGRATE"; do
    printf '%s="%s"\n' "${kv%%=*}" "$(safe "${kv#*=}")"
  done
} | tee "$CACHE" 2>/dev/null
design_skill
exit 0
