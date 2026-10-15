#!/usr/bin/env bash
# PostToolUse(Edit|Write): catch the Laravel mistakes that are cheap to detect by reading
# the file and expensive to detect in production — config caching, mass assignment, raw
# SQL, N+1, and the framework layout changes the model's training data predates.
# Definite errors -> exit 2 (Claude is told to fix them). Heuristics -> advisory context.
#   LARAVEL_WF_PHP_GUARD=warn  -> never block, advise only
#   LARAVEL_WF_PHP_GUARD=off   -> disable
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
MODE="${LARAVEL_WF_PHP_GUARD:-enforce}"
[ "$MODE" = off ] && exit 0
[ -f "$ROOT/artisan" ] || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
# Run standalone (hook JSON on stdin) or from post-edit.sh, which parses once and sets LARAVEL_WF_FILE.
if [ -n "${LARAVEL_WF_FILE:-}" ]; then FILE="$LARAVEL_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
case "$FILE" in
  *.blade.php) exit 0 ;;                 # guard-blade.sh owns those
  *.php) ;;
  *) exit 0 ;;
esac
case "$FILE" in
  */vendor/*|*/node_modules/*|*/storage/framework/*|*/bootstrap/cache/*) exit 0 ;;
esac

REL="${FILE#$ROOT/}"
BODY="$(cat "$FILE")"
# Comment-free view of the file, so a rule never fires on an example inside a docblock.
CODE="$(printf '%s' "$BODY" | sed -E 's://.*$::' | sed -E 's:/\*.*\*/::' | grep -vE '^\s*\*')"

MAJOR=0
eval "$("$SELF_DIR/stack.sh" 2>/dev/null)" || true
case "${LARAVEL_VERSION:-}" in v*) MAJOR="${LARAVEL_VERSION#v}"; MAJOR="${MAJOR%%.*}" ;; [0-9]*) MAJOR="${LARAVEL_VERSION%%.*}" ;; esac

IN_CONFIG=0;   case "$REL" in config/*) IN_CONFIG=1 ;; esac
IN_TEST=0;     case "$REL" in tests/*|*/Tests/*) IN_TEST=1 ;; esac
IN_MIGRATION=0; case "$REL" in database/migrations/*) IN_MIGRATION=1 ;; esac
IN_CONTROLLER=0; case "$REL" in app/Http/Controllers/*) IN_CONTROLLER=1 ;; esac
IN_MODEL=0;    case "$REL" in app/Models/*) IN_MODEL=1 ;; esac
IN_REQUEST=0;  case "$REL" in app/Http/Requests/*) IN_REQUEST=1 ;; esac
IN_ROUTES=0;   case "$REL" in routes/*) IN_ROUTES=1 ;; esac

ERRORS=(); WARNS=()
err()  { ERRORS+=("$1"); }
warn() { WARNS+=("$1"); }
has()  { grep -qE -- "$1" <<<"$CODE"; }
lines() { grep -nE -- "$1" <<<"$CODE" | cut -d: -f1 | tr '\n' ' ' | sed 's/ $//'; }

# --- hard errors --------------------------------------------------------------

# env() outside config/ is null in production the moment `config:cache` runs.
if [ "$IN_CONFIG" = 0 ] && [ "$IN_TEST" = 0 ] && has '(^|[^_[:alnum:]])env\('; then
  err "\`env()\` is called outside config/ (line(s) $(lines '(^|[^_[:alnum:]])env\(')). After \`php artisan config:cache\` — which every production deploy runs — env() returns null and the feature silently breaks. Add the value to a config/*.php file and read it with config('file.key')."
fi

# Framework layout the model's training data predates.
if [ "$MAJOR" -ge 11 ] 2>/dev/null; then
  case "$REL" in
    app/Http/Kernel.php)
      err "Laravel $MAJOR has no app/Http/Kernel.php. Register middleware and middleware groups in bootstrap/app.php via ->withMiddleware(fn (Middleware \$m) => ...)." ;;
    app/Console/Kernel.php)
      err "Laravel $MAJOR has no app/Console/Kernel.php. Schedule commands in routes/console.php (Schedule::command(...)) and let commands autoregister from app/Console/Commands." ;;
    app/Providers/RouteServiceProvider.php)
      # Legal in 11+ *if* it is registered in bootstrap/providers.php. Unregistered, it is dead code.
      grep -q 'RouteServiceProvider::class' "$ROOT/bootstrap/providers.php" 2>/dev/null ||
        err "Laravel $MAJOR has no RouteServiceProvider by default and this one is not listed in bootstrap/providers.php, so none of it runs. Either register it there or move the route files and rate limiters into bootstrap/app.php via ->withRouting(...)." ;;
    app/Exceptions/Handler.php)
      err "Laravel $MAJOR has no app/Exceptions/Handler.php. Configure exception rendering/reporting in bootstrap/app.php via ->withExceptions(...)." ;;
  esac
  if [ "$IN_CONTROLLER" = 1 ] && has '\$this->middleware\('; then
    err "\$this->middleware() in a controller constructor was removed in Laravel 11. Either attach the middleware on the route, or implement Illuminate\\Routing\\Controllers\\HasMiddleware and return them from \`public static function middleware(): array\`."
  fi
fi

# Raw SQL built by interpolation.
if has '(DB::raw|whereRaw|havingRaw|orderByRaw|selectRaw|joinRaw|DB::(statement|select|insert|update|delete))\([^)]*(\$|\{\$)'; then
  err "Raw SQL is built with an interpolated PHP variable (line(s) $(lines '(DB::raw|whereRaw|havingRaw|orderByRaw|selectRaw|joinRaw|DB::(statement|select|insert|update|delete))\([^)]*(\$|\{\$)')). That is SQL injection whenever the value reaches a request. Pass bindings instead: whereRaw('col = ?', [\$value]), or use the query builder."
fi

# Mass assignment straight off the request.
MASS='(::|->)(create|update|fill|forceFill|firstOrCreate|updateOrCreate)\([^)]*(\$request|request\(\))->all\(\)'
if has "$MASS"; then
  err "\$request->all() is passed into a write (line(s) $(lines "$MASS")). Every field the client sends becomes a column write, limited only by \$fillable. Use \$request->validated() from a FormRequest, or \$request->only([...])."
fi

# Debug statements that halt or leak in production.
if [ "$IN_TEST" = 0 ] && has '(^|[^_>[:alnum:]])(dd|dump|ddd|var_dump|print_r|ray)\('; then
  err "Debug output left in $REL (line(s) $(lines '(^|[^_>[:alnum:]])(dd|dump|ddd|var_dump|print_r|ray)\(')). dd()/dump() halt or corrupt the response in production. Remove them; use Log::debug() if you need a trace."
fi

# Code execution primitives.
if has '(^|[^_[:alnum:]])(eval|extract|unserialize|assert)\s*\('; then
  err "$REL uses eval/extract/unserialize/assert (line(s) $(lines '(^|[^_[:alnum:]])(eval|extract|unserialize|assert)\s*\(')). Each one turns data into code. Use json_decode() for payloads, and explicit variables instead of extract()."
fi

# A FormRequest that authorizes nothing.
if [ "$IN_REQUEST" = 1 ] &&
   grep -Pzoq -- 'function authorize\([^)]*\)[^{]*\{\s*return true;\s*\}' <<<"$CODE" 2>/dev/null; then
  warn "$REL::authorize() returns true unconditionally, so this request is allowed for anyone who can reach the route. That is correct only if the route's middleware already does the whole check — otherwise call the policy here (\$this->user()->can('update', \$this->route('model')))."
fi

# --- advisories ---------------------------------------------------------------

# N+1: a query inside a loop.
if grep -Pzoq -- '(foreach|while|for)\s*\([^)]*\)\s*\{[^}]*(->(get|first|count|sum|exists|pluck|find)\(|::(where|find|all)\()' <<<"$CODE" 2>/dev/null; then
  warn "A query runs inside a loop in $REL — that is an N+1. Eager-load the relation (->with('rel')) or hoist the query out and key the result with ->keyBy()."
fi

if has '::all\(\)' && [ "$IN_TEST" = 0 ] && [ "$IN_MIGRATION" = 0 ]; then
  warn "Model::all() in $REL loads the entire table into memory. Add constraints and ->paginate() / ->chunkById() unless the table is genuinely small and bounded."
fi

if [ "$IN_CONTROLLER" = 1 ]; then
  if has '::(where|find|first|create|update)\(' && ! has '(Service|Repository|Action|Query)'; then
    warn "$REL queries models directly. That is fine for a simple read; once a method holds more than a query and a redirect, move the work behind ${DIR_SERVICES:-app/Services} or an action class and keep the controller to request-in / response-out."
  fi
  BIGGEST="$(awk '/function [a-zA-Z_]+\(/{if(n>0) print n; n=0} {n++} END{if(n>0) print n}' <<<"$CODE" | sort -rn | head -1)"
  [ "${BIGGEST:-0}" -gt 60 ] 2>/dev/null &&
    warn "$REL has a ~${BIGGEST}-line controller method. Extract the work into a service/action; a controller method that long is untestable and always ends up duplicated."
  has 'validate\(\[' && warn "Inline \$request->validate([...]) in $REL. A FormRequest (app/Http/Requests/) keeps the rules and the authorization together and out of the controller."
fi

if [ "$IN_MODEL" = 1 ]; then
  has 'class .* extends Model' && ! has '\$(fillable|guarded)' &&
    warn "$REL declares no \$fillable (or \$guarded). Without it, mass assignment is either wide open or silently blocked depending on the Laravel version. State it explicitly."
  has '\$guarded\s*=\s*\[\]' &&
    warn "\$guarded = [] in $REL disables mass-assignment protection entirely — any validated-away field can still be written from a ->fill(). Prefer an explicit \$fillable."
  has '(function .*Attribute\(|protected function [a-z])' && has '::(where|find|get)\(' &&
    warn "An accessor in $REL appears to run a query. Accessors are evaluated per model instance, so a list of 50 rows fires 50 queries — expose it as a relation and eager-load it."
fi

if [ "$IN_MIGRATION" = 1 ]; then
  has 'function up\(' && ! has 'function down\(' &&
    warn "$REL has no down() — the migration cannot be rolled back. Write the inverse, or state in the file why it is deliberately irreversible."
  has 'foreignId\(' && ! has '(constrained|foreign)\(' &&
    warn "foreignId() in $REL without ->constrained() creates a plain column with no foreign key. Add ->constrained() (and an explicit ->onDelete()) if a real relation is intended."
  has '(->string\(|->integer\()' && ! has '(->index\(|->unique\(|primary)' &&
    warn "No index declared in $REL. Any column you will filter, join or sort by needs one — adding it later against a populated table is a migration you have to schedule."
fi

if [ "$IN_ROUTES" = 1 ]; then
  has 'function \(\)[^;]*(::where|DB::|->get\(\))' &&
    warn "A route closure in $REL queries the database. Closure routes cannot be cached (\`route:cache\` fails), so point the route at a controller instead."
fi

if has 'Cache::(remember|rememberForever|put)\(' && ! has '(Cache::(forget|tags|flush)|clearCache|Observer)'; then
  warn "$REL writes to the cache but nothing here invalidates it. Decide now what busts this key — a model observer, a ->tags() group, or an explicit Cache::forget() on write — or the stale value outlives the change that should have replaced it."
fi

if has '(Storage::|file\(|->store)' && has '\$request->file\(' && ! has '(validate|validated|mimes|image|max:)'; then
  warn "An upload in $REL is stored without a validated mime/size rule. Add mimes:/image/max: rules in the FormRequest before it reaches the disk."
fi

# Only the FIRST argument is the column/direction. `where('col', $request->x)` binds a value
# and is perfectly safe; `where($request->col, ...)` and `orderBy($request->sort)` are not.
if [ "$IN_TEST" = 0 ] && has '(->|::)(where|orderBy|orderByDesc|having|groupBy)\([[:space:]]*(\$request->|request\(\)->|\$_GET)'; then
  warn "A request value is used as a column or direction in $REL. Column names and sort directions cannot be bound as parameters — whitelist the allowed values before they reach the builder."
fi

# --- Laravel 13 (verified against laravel.com/docs/13.x/upgrade, see references/laravel13.md) ---
if [ "$MAJOR" -ge 13 ] 2>/dev/null; then
  has 'VerifyCsrfToken|ValidateCsrfToken' &&
    warn "Laravel 13 renamed the CSRF middleware to Illuminate\\Foundation\\Http\\Middleware\\PreventRequestForgery (it also checks Sec-Fetch-Site). VerifyCsrfToken/ValidateCsrfToken are deprecated aliases — reference PreventRequestForgery, e.g. ->withoutMiddleware([PreventRequestForgery::class]) in tests."
  if [ "${CACHE_SERIALIZABLE:-}" = false ] && has 'Cache::(remember|rememberForever|flexible|put|forever|add)\(' &&
     has '(->(get|first|paginate|all|find)\(\)|::(all|find|first)\(|new [A-Z])' && ! has '->(toArray|all\(\)->toArray|pluck)\('; then
    warn "$REL appears to cache PHP objects (models/collections). With cache.serializable_classes => false (the Laravel 13 default, set in this project) they won't unserialize. Cache plain arrays (->toArray()), or list the classes in config/cache.php 'serializable_classes'."
  fi
  has '->upsert\([^,]+,[[:space:]]*\[\][[:space:]]*[,)]' &&
    err "upsert() with an empty uniqueBy now throws InvalidArgumentException in Laravel 13. Pass the unique column(s)."
fi

# --- Redis, cache, uploads, images (references/redis-and-cache.md, files-and-images.md) ---
if [ "$IN_TEST" = 0 ]; then
  has 'Redis::(keys|command\([[:space:]]*.keys.)' &&
    warn "Redis KEYS in $REL walks the whole keyspace and blocks the server while it does. Use Redis::scan(), cache tags, or a key-set you maintain."
  has 'Cache::(store\([^)]*\)->)?flush\(\)' &&
    warn "Cache::flush() in $REL wipes the entire store and ignores the cache prefix (Laravel docs). On a shared Redis that's every app's cache. Invalidate by key or tag instead."
  case "${CACHE_STORE:-}" in file|database|dynamodb|storage)
    has 'Cache::tags\(' &&
      warn "Cache::tags() in $REL, but this project's cache store is '$CACHE_STORE' — tags are not supported on file, database, dynamodb or storage stores. Use explicit keys + Cache::forget(), or move the cache to redis." ;;
  esac
  has 'getClientOriginal(Name|Extension)\(' && has '(store|storeAs|storePublicly|storePubliclyAs|putFileAs|Storage::)' &&
    warn "The client's file name/extension is used near storage code in $REL. Laravel calls getClientOriginalName()/Extension() unsafe — store with store()/storePublicly() (random hashName) or build the name from hashName()/extension()."
  has '(Image::fromUrl|Http::(get|post|head|send)|file_get_contents|fopen)\([[:space:]]*(\$request->|request\(\)->|\$request\[|\$_(GET|POST|REQUEST))' &&
    err "A request-supplied URL is fetched server-side in $REL — that is SSRF (it can reach cloud metadata and internal services). Validate the host against an allow-list first, or don't fetch user URLs at all."
  has '(Storage::(disk\([^)]*\)->)?(get|put|delete|download|url|temporaryUrl|readStream|exists)|storeAs|putFileAs)\([[:space:]]*(\$request->(input|get|query)|request\(\)->|\$request->[a-z_]+[[:space:]]*[,)])' &&
    err "A storage path comes straight from the request in $REL — that is path traversal. Look the path up from your own database row (e.g. \$document->path) after authorizing access."
  if [ "$IN_CONTROLLER" = 1 ] && has '(->image\(|Image::(from|read))' && has '->(cover|resize|scale|contain|crop|optimize|toWebp|toAvif|toJpe?g)\('; then
    warn "Image processing runs inside the HTTP request in $REL. Laravel's docs: it is CPU/memory-intensive — store the original, then make variants in a queued job."
  fi
  has 'storePublicly(As)?\([^)]*(invoice|contract|passport|identity|statement|private|document)' &&
    warn "Something that looks private is stored with public visibility in $REL. Private files belong on a private disk/path and are served with temporaryUrl() after an authorization check."
fi

# --- report -------------------------------------------------------------------
if [ "$MODE" = warn ] && [ "${#ERRORS[@]}" -gt 0 ]; then
  WARNS=("${ERRORS[@]}" "${WARNS[@]}"); ERRORS=()
fi

for m in "${ERRORS[@]:-}"; do [ -n "$m" ] && wf_metric guard guard php file "$REL" level block; done
for m in "${WARNS[@]:-}";  do [ -n "$m" ] && wf_metric guard guard php file "$REL" level warn; done
if [ "${#ERRORS[@]}" -gt 0 ]; then
  { echo "Laravel guard blocked $REL:"; printf '  x %s\n' "${ERRORS[@]}"
    [ "${#WARNS[@]}" -gt 0 ] && printf '  ! %s\n' "${WARNS[@]}"
    echo "Fix these in $REL before continuing."; } >&2
  exit 2
fi

if [ "${#WARNS[@]}" -gt 0 ]; then
  TEXT="Laravel guard — advisory for $REL:
$(printf '  - %s\n' "${WARNS[@]}")"
  if [ "${LARAVEL_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
fi
exit 0
