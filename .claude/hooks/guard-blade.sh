#!/usr/bin/env bash
# PostToolUse(Edit|Write): catch the Blade mistakes that produce a 419, an XSS, an N+1 or a
# silently broken script tag — none of which the test suite will tell you about.
# See .claude/skills/blade-conventions/SKILL.md
#   LARAVEL_WF_BLADE_GUARD=warn  -> never block, advise only
#   LARAVEL_WF_BLADE_GUARD=off   -> disable
set -uo pipefail
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MODE="${LARAVEL_WF_BLADE_GUARD:-enforce}"
[ "$MODE" = off ] && exit 0
[ -f "$ROOT/artisan" ] || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets LARAVEL_WF_FILE.
if [ -n "${LARAVEL_WF_FILE:-}" ]; then FILE="$LARAVEL_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in *.blade.php) ;; *) exit 0 ;; esac

REL="${FILE#$ROOT/}"
BODY="$(cat "$FILE")"
# Blade comments {{-- --}} are stripped so an example inside one never trips a rule.
CODE="$(printf '%s' "$BODY" | perl -0777 -pe 's/\{\{--.*?--\}\}//gs' 2>/dev/null || printf '%s' "$BODY")"

ERRORS=(); WARNS=()
err()  { ERRORS+=("$1"); }
warn() { WARNS+=("$1"); }
has()  { grep -qE -- "$1" <<<"$CODE"; }
lines() { grep -nE -- "$1" <<<"$CODE" | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//'; }

# --- hard errors --------------------------------------------------------------

# A POST/PUT/PATCH/DELETE form without @csrf is a guaranteed 419 in the browser.
if has '<form[^>]*method=["'"'"']?(POST|post)' && ! has '@csrf'; then
  err "A POST form in $REL has no @csrf. Every state-changing form needs it or Laravel rejects the request with a 419 — add @csrf directly inside <form>, and @method('PUT'|'PATCH'|'DELETE') if the route is not POST."
fi

# Unescaped output of request-controlled data is stored/reflected XSS.
RAW_REQ='\{!!.*(request\(|\$_GET|\$_POST|old\(|Request::)'
if has "$RAW_REQ"; then
  N="$(lines "$RAW_REQ")"
  err "$REL prints request data unescaped with {!! !!} (line(s) $N). That is an XSS hole. Use {{ }}, which escapes."
fi

# Queries in a view: the view is rendered after the controller has finished, so every one
# of these is an unbatched query the controller could have eager-loaded.
VIEW_QUERY='(::(where|find|findOrFail|all|first|latest|orderBy|with|count)\(|DB::(table|select|raw)\()'
if has "$VIEW_QUERY"; then
  N="$(lines "$VIEW_QUERY")"
  err "$REL queries the database (line(s) $N). A view renders data it was given; it does not fetch it. Move the query into the controller, a view composer (${DIR_COMPOSERS:-app/View/Composers}), or the component's class."
fi

# env() is null in production once config is cached.
if has '(^|[^_[:alnum:]])env\('; then
  err "\`env()\` in $REL returns null in production once \`config:cache\` has run. Use config('...') — and prefer passing the value in from the controller."
fi

# --- advisories ---------------------------------------------------------------

if has '\{!!' && ! has "$RAW_REQ"; then
  N="$(lines '\{!!')"
  warn "Unescaped {!! !!} in $REL (line(s) $N). Safe only if the HTML is authored by a trusted editor and sanitized on write. If it is user content, escape it or run it through a sanitizer first."
fi

# Blade escaping inside a <script> is HTML escaping, not JS escaping.
if grep -Pzoq -- '<script(?![^>]*type="application/json")[^>]*>.*?\{\{' <<<"$CODE" 2>/dev/null; then
  warn "$REL interpolates {{ }} inside <script>. Blade escapes for HTML, not for JavaScript, so a quote or </script> in the value breaks or hijacks the script. Use @js(\$value) (or json_encode into a data-* attribute and read it with Alpine)."
fi
if has 'x-data=["'"'"'][^"'"'"']*\{\{'; then
  warn "x-data in $REL is built by interpolating {{ }}. Use @js(\$data) so the value is emitted as valid JavaScript rather than HTML-escaped text."
fi

# Assets
if has '(<script[^>]*src=|<link[^>]*href=)[^>]*(asset\(["'"'"']?(build|js|css)/|/build/)' && ! has '@vite'; then
  warn "$REL links a built asset by hand. Use @vite(['resources/...']) so the hashed filename from the manifest is used and hot reload works in dev."
fi

# Logic that has outgrown a template
PHPBLOCKS="$(grep -c '@php' <<<"$CODE" || true)"
[ "${PHPBLOCKS:-0}" -gt 2 ] 2>/dev/null &&
  warn "$REL has $PHPBLOCKS @php blocks. Anything more than a one-line assignment belongs in the controller, an accessor, or a view model — templates that compute are the ones nobody can test."
if grep -Pzoq -- '@php\b(?!\s*\()(?:(?!@endphp).)*\n(?:(?!@endphp).)*\n(?:(?!@endphp).)*\n' <<<"$CODE" 2>/dev/null; then
  warn "A multi-line @php block in $REL. Move that computation out of the template."
fi

NEST="$(grep -cE '@(if|unless|isset|empty)\b' <<<"$CODE" || true)"
[ "${NEST:-0}" -gt 12 ] 2>/dev/null &&
  warn "$REL has ${NEST} conditional directives. Split it into components or push the branching into the data the controller passes in."

# N+1 shapes that are visible from the template alone
if grep -Pzoq -- '@foreach(?:(?!@endforeach).)*->(count|sum|avg|first|exists)\(\)' <<<"$CODE" 2>/dev/null; then
  warn "A ->count()/->first() runs inside an @foreach in $REL — one query per row. Use withCount()/with() in the controller and read the loaded value here."
fi

# Accessibility and link hygiene — cheap to fix now, expensive to retrofit
has '<img[^>]*>' && ! has '<img[^>]*alt=' &&
  warn "An <img> in $REL has no alt attribute. Give it real alt text, or alt=\"\" if it is purely decorative."
has 'target=["'"'"']_blank' && ! has 'rel=["'"'"'][^"'"'"']*noopener' &&
  warn "target=\"_blank\" without rel=\"noopener\" in $REL hands the opened page a reference to this window."
has '<a[^>]*href=["'"'"']#["'"'"'][^>]*(onclick|@click|x-on:click)' &&
  warn "A link in $REL is really a button (href=\"#\" plus a click handler). Use <button type=\"button\">: it is keyboard-operable and announced correctly."
has '<form' && has '<button' && ! has '<button[^>]*type=' &&
  warn "A <button> inside a form in $REL has no type attribute, so it defaults to type=\"submit\". Set type=\"button\" on anything that is not the submit control."

# Unbalanced directives — the error Blade reports is always in the compiled file, never here
for d in if foreach forelse for while section push; do
  case "$d" in
    section) OPEN="$(grep -cE '@section\b[^)]*\)[[:space:]]*$' <<<"$CODE" || true)"; CLOSE="$(grep -cE '@(endsection|stop|show)\b' <<<"$CODE" || true)" ;;
    forelse) OPEN="$(grep -cE '@forelse\b' <<<"$CODE" || true)"; CLOSE="$(grep -cE '@endforelse\b' <<<"$CODE" || true)" ;;
    *) OPEN="$(grep -cE "@$d\b" <<<"$CODE" || true)"; CLOSE="$(grep -cE "@end$d\b" <<<"$CODE" || true)" ;;
  esac
  [ "${OPEN:-0}" -ne "${CLOSE:-0}" ] 2>/dev/null &&
    warn "@$d appears $OPEN time(s) but @end$d $CLOSE time(s) in $REL. Blade will report this as a parse error in the compiled file, with a line number that does not exist in this one."
done

# --- report -------------------------------------------------------------------
if [ "$MODE" = warn ] && [ "${#ERRORS[@]}" -gt 0 ]; then
  WARNS=("${ERRORS[@]}" "${WARNS[@]}"); ERRORS=()
fi

for m in "${ERRORS[@]:-}"; do [ -n "$m" ] && wf_metric guard guard blade file "$REL" level block; done
for m in "${WARNS[@]:-}";  do [ -n "$m" ] && wf_metric guard guard blade file "$REL" level warn; done
if [ "${#ERRORS[@]}" -gt 0 ]; then
  { echo "Blade guard blocked $REL:"; printf '  x %s\n' "${ERRORS[@]}"
    [ "${#WARNS[@]}" -gt 0 ] && printf '  ! %s\n' "${WARNS[@]}"
    echo "Fix these in $REL before continuing."; } >&2
  exit 2
fi

if [ "${#WARNS[@]}" -gt 0 ]; then
  TEXT="Blade guard — advisory for $REL:
$(printf '  - %s\n' "${WARNS[@]}")"
  if [ "${LARAVEL_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
fi
exit 0
