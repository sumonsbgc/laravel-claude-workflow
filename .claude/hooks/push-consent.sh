#!/usr/bin/env bash
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r '.prompt // ""' 2>/dev/null)"
else
  PROMPT="$(printf '%s' "$INPUT" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo $d["prompt"]??"";' 2>/dev/null)"
fi
FIRST="${PROMPT%%$'\n'*}"
[[ "$FIRST" =~ ^[[:space:]]*/laravel:sync([[:space:]]|$) ]] || exit 0
mkdir -p "$ROOT/.claude/.cache" 2>/dev/null || exit 0
date +%s > "$ROOT/.claude/.cache/push-consent"
exit 0
