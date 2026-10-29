#!/usr/bin/env bash
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INPUT="$(cat)"
field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r ".$1 // \"\"" 2>/dev/null
  else
    printf '%s' "$INPUT" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $d[$argv[1]]??"";' "$1" 2>/dev/null
  fi
}
PROMPT="$(field prompt)"
SESSION="$(field session_id)"
FIRST="${PROMPT%%$'\n'*}"
[[ "$FIRST" =~ ^[[:space:]]*/laravel:sync([[:space:]]|$) ]] || exit 0
[[ "$SESSION" =~ ^[A-Za-z0-9_-]+$ ]] || exit 0
mkdir -p "$ROOT/.claude/.cache" 2>/dev/null || exit 0
printf '%s %s\n' "$(date +%s)" "$SESSION" > "$ROOT/.claude/.cache/push-consent"
exit 0
