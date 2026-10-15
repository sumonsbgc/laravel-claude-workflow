#!/usr/bin/env bash
# PostToolUse(Edit|Write): format the touched file with the project's own toolchain
# (never installs anything), and remember that it changed so the Stop hook knows what
# to syntax-check.
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -f "$ROOT/artisan" ] || exit 0                      # not a Laravel project
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
if [ -n "${LARAVEL_WF_FILE:-}" ]; then FILE="$LARAVEL_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  *.php|*.js|*.ts|*.css|*.json|*.md) ;;   # *.php includes *.blade.php
  *) exit 0 ;;
esac

mkdir -p "$ROOT/.claude/.cache"
case "$FILE" in
  *.blade.php) ;;                                     # php -l cannot parse Blade
  *.php) printf '%s\n' "$FILE" >> "$ROOT/.claude/.cache/dirty-files" ;;
esac

case "$FILE" in
  *.blade.php) ;;                                     # Pint does not format Blade
  *.php)
    # Pint reads the project's own pint.json / preset. Never pass a style flag here.
    [ -x "$ROOT/vendor/bin/pint" ] && "$ROOT/vendor/bin/pint" --quiet "$FILE" >/dev/null 2>&1 || true
  ;;
  *.js|*.ts|*.css|*.json|*.md)
    [ -x "$ROOT/node_modules/.bin/prettier" ] &&
      "$ROOT/node_modules/.bin/prettier" --write --log-level error "$FILE" >/dev/null 2>&1 || true
  ;;
esac
exit 0
