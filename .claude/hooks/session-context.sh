#!/usr/bin/env bash
# SessionStart: tell Claude what this particular Laravel project actually is,
# so agents/commands stop guessing (Pest vs PHPUnit, Blade vs Livewire vs Inertia,
# Tailwind v3 vs v4, which cache store, where the service/policy layers live).
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$ROOT/composer.json" ] || exit 0
. "$SELF_DIR/_lib.sh"
eval "$(bash "$SELF_DIR/stack.sh")"
[ -n "$LARAVEL_VERSION" ] || exit 0   # not a Laravel project; stay quiet
bash "$SELF_DIR/bash-guard.sh" --snapshot >/dev/null 2>&1   # baseline for shell-change detection
# shellcheck disable=SC2088  # a literal "~" for display, not a path to expand
if [ "$SELF_DIR" = "$ROOT/.claude/hooks" ]; then HELPERS=".claude/hooks"; else HELPERS="~/.claude/hooks"; fi
KIT_VERSION="$(cat "$ROOT/.claude/laravel-workflow.version" 2>/dev/null || cat "$SELF_DIR/../laravel-workflow.version" 2>/dev/null || echo unknown)"

# Version-specific guidance: verified notes per major live in the skill's references.
if [ "${LARAVEL_MAJOR:-0}" -ge 13 ] 2>/dev/null; then
  VERREF="Laravel $LARAVEL_MAJOR: read \`laravel-conventions/references/laravel13.md\` before touching CSRF/middleware, cache or session config — it lists what changed in 13.${CACHE_SERIALIZABLE:+ cache.serializable_classes is false here: never cache PHP objects (models, collections); cache arrays.}"
else
  VERREF="Laravel ${LARAVEL_MAJOR:-?}: the rules in \`laravel-conventions\` apply as written."
fi
if [ -n "${BOOST:-}" ]; then
  VERREF="$VERREF Laravel Boost $BOOST is installed${BOOST_MCP:+ (MCP server in .mcp.json)}: use its tools (mcp__laravel-boost__*): search-docs before relying on memory for any API (it overrides the skill), database-schema instead of reading migrations, last-error/read-log-entries when something fails, browser-logs for frontend errors.${AI_RULES:+ Project rules live in .ai/rules — read .ai/rules/index.md before editing a matching path.}"
else
  VERREF="$VERREF Laravel Boost is not installed (first-party MCP: version-matched docs, DB schema, error logs) — /laravel:setup can recommend it."
fi

CSS="none"
[ -n "$TAILWIND_VERSION" ] && CSS="tailwind $TAILWIND_VERSION"
[ -n "$TAILWIND_INSTALLED" ] && CSS="tailwind $TAILWIND_INSTALLED (installed)"
[ -z "$TAILWIND_VERSION" ] && [ -n "$BOOTSTRAP_VERSION" ] && CSS="bootstrap $BOOTSTRAP_VERSION"

FORMATTER="none"
[ "$PINT" = yes ] && FORMATTER="pint"
[ "$PINT" = declared ] && FORMATTER="pint (declared, vendor/bin/pint missing — run composer install)"

LAYERS=""
for d in "$DIR_SERVICES" "$DIR_ACTIONS" "$DIR_POLICIES" "$DIR_OBSERVERS" "$DIR_COMPOSERS" "$DIR_LIVEWIRE"; do
  [ -n "$d" ] && LAYERS="${LAYERS:+$LAYERS, }$d"
done

# Accumulated project knowledge, written by the task runner. Injected so no session has to
# rediscover it. Comments and empty sections are stripped; hard-capped so it can never dominate.
CONTEXT=""
CTX_FILE="$ROOT/.claude/project-context.md"
if [ -f "$CTX_FILE" ]; then
  # Strip single-line comments first: a sed range never ends on the line it starts,
  # so '/<!--/,/-->/d' alone would swallow everything up to the *next* comment.
  # Then drop headings that have no content under them.
  CTX_FULL="$(sed -E 's/<!--.*-->//' "$CTX_FILE" | sed -E '/<!--/,/-->/d' \
    | awk '/^#/ { hdr=$0; next } NF { if (hdr != "") { print hdr; hdr="" } print }')"
  CTX_BODY="$(printf '%s' "$CTX_FULL" | head -c 4000)"
  # Cut at a line boundary, and say so: a silently dropped Gotchas section is worse than a warning.
  if [ "${#CTX_FULL}" -gt 4000 ]; then
    CTX_BODY="$(printf '%s' "$CTX_BODY" | sed '$d')
[project-context.md is ${#CTX_FULL} characters; only the first 4000 were loaded — merge and prune it to under ~60 lines so nothing is dropped]"
  fi
  if [ "$(printf '%s' "$CTX_BODY" | grep -vcE '^#|^$')" -gt 0 ] 2>/dev/null; then
    CONTEXT="

Known about this codebase (.claude/project-context.md — keep it current, it is why you do not have to rediscover this):
$CTX_BODY"
  fi
fi

TASKS=""
TDIR="$(CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF_DIR/tasks.sh" dir 2>/dev/null)"
if [ -n "$TDIR" ] && [ -d "$ROOT/$TDIR" ] && [ -x "$SELF_DIR/tasks.sh" ]; then
  TODO="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count todo 2>/dev/null || echo 0)"
  DOING="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count doing 2>/dev/null || echo 0)"
  BLOCKED="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count blocked 2>/dev/null || echo 0)"
  DRAFT="$(CLAUDE_PROJECT_DIR="$ROOT" "$SELF_DIR/tasks.sh" count draft 2>/dev/null || echo 0)"
  PARTS=""
  [ "${DRAFT:-0}" -gt 0 ] 2>/dev/null   && PARTS="$DRAFT draft (awaiting approval)"
  [ "${TODO:-0}" -gt 0 ] 2>/dev/null    && PARTS="${PARTS:+$PARTS, }$TODO todo"
  [ "${DOING:-0}" -gt 0 ] 2>/dev/null   && PARTS="${PARTS:+$PARTS, }$DOING in progress"
  [ "${BLOCKED:-0}" -gt 0 ] 2>/dev/null && PARTS="${PARTS:+$PARTS, }$BLOCKED blocked"
  [ -n "$PARTS" ] && TASKS="
- Tasks: $PARTS — \`/laravel:task\` runs the next one, \`/laravel:task list\` shows them all."
fi

TEXT="Detected stack (laravel-workflow $KIT_VERSION, auto-detected at session start — this report is the source of truth for the stack):
- Kit helpers: \`$HELPERS\` — run \`bash $HELPERS/tasks.sh …\` (and run-tasks.sh, verify.sh) from there.
- Laravel: $LARAVEL_VERSION on PHP ${PHP_VERSION:-unknown}${PHP_REQUIRED:+ (requires $PHP_REQUIRED)}
- $VERREF
- View layer: $VIEW_LAYER${LIVEWIRE_VERSION:+ $LIVEWIRE_VERSION}${ALPINE_VERSION:+ | Alpine.js $ALPINE_VERSION} | CSS: $CSS${ASSET_BUILD:+ | assets: $ASSET_BUILD}
- Routes: ${ROUTE_FILES:-none} | App layers present: ${LAYERS:-controllers + models only}
- Drivers: db=${DB_CONNECTION:-?} cache=${CACHE_STORE:-?} queue=${QUEUE_CONNECTION:-?} session=${SESSION_DRIVER:-?}${REDIS_CLIENT:+ | redis client: $REDIS_CLIENT} | php ext: ${PHP_EXT:-none of redis/gd/imagick}${RICH_EDITOR:+
- Rich-text editor: $RICH_EDITOR}
- Files: disk=${FS_DISK:-local}${S3_ADAPTER:+ | S3 adapter installed}${CDN_URL:+ | AWS_URL (CDN host) set} | images: ${IMAGES:-no image library}
- Auth: ${AUTH_STACK:-hand-rolled or none detected}${PERMISSIONS:+ | permissions: $PERMISSIONS}${ADMIN_PANEL:+ | admin panel: $ADMIN_PANEL}
- Tests: ${TEST_RUNNER:-none}${TEST_VERSION:+ $TEST_VERSION} | Formatter: $FORMATTER | Static analysis: ${STATIC_ANALYSIS:-none}${DESIGN_SKILL:+
- Design: the \`frontend-design\` skill is available — load it when building new UI or restyling, and not for refactors, fixes, or views that must match existing siblings.}
- Verify commands: test=\`${CMD_TEST:-n/a}\` lint=\`${CMD_LINT:-n/a}\` analyse=\`${CMD_ANALYSE:-n/a}\` build=\`${CMD_BUILD:-n/a}\` dev=\`${CMD_DEV}\`
- Repo map: \`bash $HELPERS/tasks.sh map\` prints models with relations, controllers with actions, routes, tables and views (cached, regenerated when files change). Read it before exploring with grep/ls.

Use these exact commands rather than inventing them. Do not add a package that is not listed here — no Livewire in a Blade+Alpine project, no spatie/laravel-permission over a hand-rolled RBAC, no Tailwind classes if Tailwind is absent. Write classes for the installed Tailwind version only; a utility from a newer minor silently emits no CSS. Never call \`env()\` outside \`config/\` — it returns null once config is cached in production.$CONTEXT$TASKS"

wf_context SessionStart "$TEXT"
