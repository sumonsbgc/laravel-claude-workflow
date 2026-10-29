#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="$(cat)"
field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$1 // \"\""
  else
    printf '%s' "$INPUT" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $argv[1]===".tool_name" ? ($d["tool_name"]??"") : ($d["tool_input"]["command"]??"");' "$1" 2>/dev/null
  fi
}

allow() {
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"laravel-workflow helper: %s"}}\n' "$1"
  exit 0
}
plain() { [[ "$1" != *[\$\`\;\&\|\<\>\\\*\?\{\}\(\)]* ]] && [[ "$1" != *$'\n'* ]]; }
paths_only() {
  local a
  read -ra ARGS <<<"$1"
  [ "${#ARGS[@]}" -gt 0 ] || return 1
  for a in "${ARGS[@]}"; do [[ "$a" =~ ^[A-Za-z0-9_./@][A-Za-z0-9_./@:-]*$ ]] || return 1; done
}

TOOL="$(field .tool_name)"
case "$TOOL" in
  mcp__laravel-boost__search-docs|mcp__laravel-boost__database-schema|mcp__laravel-boost__database-query|\
  mcp__laravel-boost__application-info|mcp__laravel-boost__last-error|mcp__laravel-boost__read-log-entries|\
  mcp__laravel-boost__browser-logs|mcp__laravel-boost__get-absolute-url|mcp__laravel-boost__database-connections)
    allow "${TOOL#mcp__laravel-boost__}" ;;
  mcp__*) exit 0 ;;
esac

CMD="$(field .tool_input.command)"
[ -n "$CMD" ] || exit 0

H="$(printf '%s' "$SELF_DIR" | sed 's/[]\\.^$*+?(){}|[]/\\&/g')"
HELPER_RE="^bash $H/(tasks|stack|repo-map|verify-browser|git-sync)\\.sh( .*)?$"

FIRST="${CMD%%$'\n'*}"
TQ="'"
if [ "$FIRST" != "$CMD" ] &&
   [[ "$FIRST" =~ ^bash\ $H/tasks\.sh\ new\ [0-9]{3,}-[a-z0-9]+(-[a-z0-9]+)*\ \<\<\ ?($TQ([A-Za-z_]+)$TQ|\"([A-Za-z_]+)\")$ ]]; then
  TAG="${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
  BODY="${CMD#*$'\n'}"; BODY="${BODY%"${BODY##*[![:space:]]}"}"
  [ "${BODY##*$'\n'}" = "$TAG" ] && [ "$(grep -cxF -- "$TAG" <<<"$BODY")" = 1 ] && allow "tasks.sh new"
  exit 0
fi

plain "$CMD" || exit 0

[[ "$CMD" =~ $HELPER_RE ]] && allow "${BASH_REMATCH[1]}.sh"

case "$CMD" in
  'printenv LARAVEL_WF_DEV_URL'|'git status'|'php -v'|'composer show'|'npm run build'|\
  'php artisan route:list'|'php artisan about'|'php artisan migrate:status'|'php artisan migrate --pretend'|\
  'php artisan config:clear'|'php artisan view:clear')
    allow "$CMD" ;;
esac
[[ "$CMD" == "php -l "* ]] && paths_only "${CMD#php -l }" && allow "php -l"

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
eval "$(CLAUDE_PROJECT_DIR="$ROOT" bash "$SELF_DIR/stack.sh" 2>/dev/null | grep -E '^CMD_(TEST|LINT|ANALYSE|BUILD)=')"
for c in "${CMD_TEST:-}" "${CMD_LINT:-}" "${CMD_ANALYSE:-}" "${CMD_BUILD:-}"; do
  [ -n "$c" ] || continue
  [ "$CMD" = "$c" ] && allow "verify command"
  if [[ "$CMD" == "$c "* ]]; then
    REST="${CMD#"$c "}"; REST="${REST#-- }"
    paths_only "$REST" && allow "verify command"
  fi
done
exit 0
