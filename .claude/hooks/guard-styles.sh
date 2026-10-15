#!/usr/bin/env bash
# PostToolUse(Edit|Write): catch Tailwind class mistakes that produce no CSS and no error —
# v3 utilities removed in v4, classes newer than the installed version, and interpolated
# class names the scanner can never see.
# See .claude/skills/blade-conventions/references/styling.md
#   LARAVEL_WF_STYLE_GUARD=off  -> disable
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ "${LARAVEL_WF_STYLE_GUARD:-on}" = off ] && exit 0
[ -f "$ROOT/artisan" ] || exit 0   # not a Laravel project
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets LARAVEL_WF_FILE.
if [ -n "${LARAVEL_WF_FILE:-}" ]; then FILE="$LARAVEL_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in *.blade.php|*.css|*.html|*.js) ;; *) exit 0 ;; esac

# Installed Tailwind major.minor — from node_modules, not the package.json range.
# From the stack cache (a `cat` on the hot path) rather than starting node on every edit.
TW="$(eval "$(bash "$SELF_DIR/stack.sh")"; printf '%s' "${TAILWIND_INSTALLED:-}")"
[ -n "$TW" ] || exit 0                      # Tailwind not installed: nothing to check
MAJOR="${TW%%.*}"; REST="${TW#*.}"; MINOR="${REST%%.*}"
[ "$MAJOR" = 4 ] || exit 0                  # v3 projects: the v4 rules don't apply

REL="${FILE#$ROOT/}"
BODY="$(cat "$FILE")"
WARNS=()
warn() { WARNS+=("$1"); }
hit() { grep -qE -- "(^|[\"' \`])$1" <<<"$BODY"; }

# --- v3 utilities that emit nothing in v4 ------------------------------------
hit '(bg|text|border|ring|divide|placeholder)-opacity-[0-9]+' && warn "Removed in v4: *-opacity-* utilities emit no CSS. Use the slash modifier — bg-black/50, text-white/70."
hit 'flex-(shrink|grow)(-0)?\b'                               && warn "Removed in v4: flex-shrink-*/flex-grow-* are now shrink-*/grow-*."
hit 'overflow-ellipsis'                                       && warn "Removed in v4: overflow-ellipsis is now text-ellipsis."
hit 'decoration-(slice|clone)'                                && warn "Removed in v4: decoration-slice/clone are now box-decoration-slice/clone."
hit 'outline-none'                                            && warn "In v4 outline-none means outline:none (no focus ring for forced-colors users). If you meant the v3 behaviour, use outline-hidden."
if [ "$MINOR" -ge 3 ] 2>/dev/null; then
  hit '(start|end)-(0|px|auto|[0-9]+|\[)'                     && warn "Deprecated in v4.3: start-*/end-* are now inset-s-*/inset-e-*."
fi

# --- v3 config that v4 ignores ------------------------------------------------
case "$FILE" in
  *.css)
    grep -qE '@tailwind[[:space:]]+(base|components|utilities)' <<<"$BODY" &&
      warn "@tailwind base/components/utilities is v3 syntax. v4 wants a single \`@import \"tailwindcss\";\` — the three directives compile to nothing."
    grep -qE '@apply' <<<"$BODY" && grep -qE '@layer[[:space:]]+components' <<<"$BODY" ||
      true
  ;;
esac
if [ -f "$ROOT/tailwind.config.js" ] || [ -f "$ROOT/tailwind.config.ts" ]; then
  case "$FILE" in
    *.css)
      grep -qE '@config' <<<"$BODY" ||
        warn "This project still has a tailwind.config.js, but v4 does not read it unless the CSS entry says \`@config \"../../tailwind.config.js\";\`. Theme values belong in @theme inside the CSS."
    ;;
  esac
fi

# --- classes newer than the installed version --------------------------------
newer() { # newer <min-minor> <regex> <message>
  [ "$MINOR" -lt "$1" ] 2>/dev/null || return 0
  grep -qE -- "(^|[\"' \`])$2" <<<"$BODY" && warn "$3 (tailwindcss $TW is installed — this class emits no CSS here)."
}
newer 1 '(text-shadow|mask-[a-z]|wrap-(break-word|anywhere)|items-[a-z-]+-safe|justify-[a-z-]+-safe)' "Utility added in Tailwind v4.1"
newer 3 '(scrollbar-(thin|auto|none|thumb-|track-|gutter-)|zoom-[0-9]|tab-[0-9]|font-features-|(m|p)b(s|e)-[0-9]|inset-(s|e|bs|be)-)' "Utility added in Tailwind v4.3"

# --- pointer cursor on interactive elements (v4 Preflight no longer sets it) ---
# Silent when the project has a base-layer rule, so this only fires where it matters.
BASE_RULE=0
for css in "$ROOT"/resources/css/*.css "$ROOT"/resources/sass/*.scss; do
  [ -f "$css" ] && grep -qE "cursor:[[:space:]]*pointer" "$css" && BASE_RULE=1 && break
done
if [ "$BASE_RULE" = 0 ]; then
  case "$FILE" in
    *.blade.php)
      if grep -qE -- "<(button|a)([[:space:]>]|$)|role=[\"']button[\"']|<x-[a-z-]*button" <<<"$BODY" && ! grep -q "cursor-pointer" <<<"$BODY"; then
        warn "Buttons/links in $REL have no pointer cursor. Tailwind v4 Preflight dropped cursor:pointer on buttons — add cursor-pointer (and disabled:cursor-not-allowed), or better, one base-layer rule in resources/css so it is never forgotten."
      fi
    ;;
  esac
fi

# --- class names the scanner can never see ------------------------------------
# Tailwind v4 scans source text. A class assembled at runtime is not in that text, so the
# utility is never generated — the page just renders unstyled.
# Only a *partial* class name is a problem: `bg-{{ $c }}-500`. A whole literal class chosen
# by a ternary — `{{ $on ? 'bg-blue-500' : 'bg-gray-200' }}` — is in the source and is fine.
grep -qE -- 'class="[^"]*([A-Za-z0-9_-]\{\{|\}\}[A-Za-z0-9_-])' <<<"$BODY" &&
  warn "A class attribute in $REL is built from a PHP expression. Tailwind never sees \`bg-{{ \$color }}-500\` in the source, so that utility is not generated. Map the value to complete class strings (match(true) { ... 'bg-red-500' }) and print the whole string."
grep -qE -- "@class\(\[[^]]*\\\$[a-zA-Z_]+[[:space:]]*\." <<<"$BODY" &&
  warn "@class([...]) in $REL concatenates a variable into a class name. Only complete literal class strings are ever generated — put the full class on each branch."

# --- report -------------------------------------------------------------------
for m in "${WARNS[@]:-}"; do [ -n "$m" ] && wf_metric guard guard styles file "$REL" level warn; done
if [ "${#WARNS[@]}" -gt 0 ]; then
  TEXT="Tailwind $TW — advisory for $REL:
$(printf '  - %s\n' "${WARNS[@]}")"
  if [ "${LARAVEL_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
fi
exit 0
