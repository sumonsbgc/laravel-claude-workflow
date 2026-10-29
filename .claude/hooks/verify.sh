#!/usr/bin/env bash
# Stop: before handing the turn back, make sure the PHP the agent just wrote actually
# parses. Failures are reported back so Claude fixes them in-turn instead of leaving a
# broken tree behind.
#   LARAVEL_WF_VERIFY=off                  -> disable
#   LARAVEL_WF_VERIFY=syntax               -> php -l on changed files (default)
#   LARAVEL_WF_VERIFY=syntax,lint          -> also pint --test on changed files
#   LARAVEL_WF_VERIFY=syntax,analyse       -> also phpstan/larastan (project config)
#   LARAVEL_WF_VERIFY=syntax,lint,analyse  -> both
#   verify.sh --baseline                   record current static-analysis errors as pre-existing
#
# php -l and pint only look at the files this turn changed. Static analysis covers the whole
# project, so errors that were already there are baselined (by the installer or the user —
# never by the agent): only NEW findings fail the turn.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MODE="${LARAVEL_WF_VERIFY:-syntax}"
[ -f "$ROOT/artisan" ] || exit 0
. "$SELF_DIR/_lib.sh"
BASELINE="$ROOT/.claude/.cache/analyse-baseline"
# raw format is "path:line:message" — drop the line number, which moves as code is edited
normalize() { sed -nE 's/^(.+):[0-9]+:(.*)$/\1: \2/p' | sort -u; }
# Last line of defence: only ever eval a command made of plain words.
cmd_ok() { [[ "$1" =~ ^[A-Za-z0-9\ ._/:=-]*$ ]]; }
analyse() { eval "$(bash "$SELF_DIR/stack.sh")"; cmd_ok "${CMD_ANALYSE:-}" || return 0; [ -n "${CMD_ANALYSE:-}" ] || return 0
            (cd "$ROOT" && eval "$CMD_ANALYSE --error-format=raw --no-progress" 2>&1); }

if [ "${1:-}" = --baseline ]; then
  mkdir -p "$ROOT/.claude/.cache"
  analyse | normalize > "$BASELINE"
  N="$(grep -c . "$BASELINE" || true)"
  wf_metric baseline errors "$N"
  echo "baseline: $N pre-existing static-analysis finding(s) recorded in .claude/.cache/analyse-baseline"
  exit 0
fi

[ "$MODE" = off ] && exit 0
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')"
else
  ACTIVE="$(printf '%s' "$INPUT" | php -r '$d=json_decode(stream_get_contents(STDIN),true); echo ($d["stop_hook_active"] ?? false) ? "true" : "false";' 2>/dev/null || echo false)"
fi
[ "$ACTIVE" = true ] && exit 0   # already looped once; never trap the agent in a Stop loop

MARK="$ROOT/.claude/.cache/dirty-files"
[ -s "$MARK" ] || exit 0
FILES="$(sort -u "$MARK" | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f"; done)"
rm -f "$MARK"
[ -n "$FILES" ] || exit 0

FAIL=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  OUT="$(php -l "$f" 2>&1)" || FAIL="$FAIL
--- syntax error ---
$OUT"
done <<< "$FILES"

if [[ "$MODE" == *lint* ]] && [ -x "$ROOT/vendor/bin/pint" ]; then
  mapfile -t FILE_ARR <<<"$FILES"
  OUT="$(cd "$ROOT" && "$ROOT/vendor/bin/pint" --test "${FILE_ARR[@]}" 2>&1)" || FAIL="$FAIL
--- pint --test failed ---
$(printf '%s' "$OUT" | tail -n 30)"
fi

if [[ "$MODE" == *analyse* ]]; then
  eval "$(bash "$SELF_DIR/stack.sh")"
  if [ -n "${CMD_ANALYSE:-}" ]; then
    if OUT="$(analyse)"; then
      : > "$BASELINE" 2>/dev/null || true          # clean: nothing is pre-existing any more
    else
      NOW="$(printf '%s\n' "$OUT" | normalize)"
      if [ -z "$NOW" ]; then
        FAIL="$FAIL
--- static analysis failed ($CMD_ANALYSE) ---
$(printf '%s' "$OUT" | tail -n 40)"
      elif [ -f "$BASELINE" ]; then
        NEW="$(comm -13 "$BASELINE" <(printf '%s\n' "$NOW"))"
        if [ -n "$NEW" ]; then
          FAIL="$FAIL
--- static analysis: $(grep -c . <<<"$NEW") new finding(s) introduced by this change ---
$(printf '%s\n' "$NEW" | head -n 40)
(Pre-existing findings are baselined and not shown. Fix only the ones above.)"
        else
          comm -12 "$BASELINE" <(printf '%s\n' "$NOW") > "$BASELINE.tmp" && mv "$BASELINE.tmp" "$BASELINE"
        fi
      else
        FAIL="$FAIL
--- static analysis failed ($CMD_ANALYSE) ---
$(printf '%s' "$OUT" | tail -n 40)
(No baseline exists. If these were already in the codebase, tell the user — they can record them with: bash $(wf_helpers "$SELF_DIR")/verify.sh --baseline. Do not run that yourself.)"
      fi
    fi
  fi
fi

if [ -n "$FAIL" ]; then
  wf_metric verify result fail
  { echo "Verification of your changes failed. Fix these, then stop:"; printf '%s\n' "$FAIL"; } >&2
  exit 2
fi
wf_metric verify result pass
exit 0
