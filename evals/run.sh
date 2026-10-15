#!/usr/bin/env bash
# End-to-end eval of the Laravel workflow: does it turn tasks into working features, and at what
# cost? Each run creates a fresh Laravel app (composer create-project), overlays the fixture
# (News model, two seeded users), adds Pest, installs the kit, runs the seeded tasks headless with
# fresh context per task, then scores every task by behaviour: real HTTP requests against
# `php artisan serve`, plus hidden Pest tests the agent never sees (including authorization).
#
#   evals/run.sh                 3 runs (network + real API spend)
#   evals/run.sh --runs 5        more runs: tighter numbers
#   evals/run.sh --budget 3      per-task spending cap in USD (default 5)
#   evals/run.sh --keep          keep the work directories
#   evals/run.sh --dry-run       set up one app, run nothing (checks the harness wiring)
#   evals/run.sh --reference     apply evals/reference/ instead of the agent: proves every check CAN
#                                pass (no API spend). Must score 5/5 before trusting real runs.
set -uo pipefail
EVALS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT="$(dirname "$EVALS")"
export EVALS
RUNS=3; BUDGET=5; KEEP=0; DRY=0; REF=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="$2"; shift ;;
    --budget) BUDGET="$2"; shift ;;
    --keep) KEEP=1 ;;
    --dry-run) DRY=1; RUNS=1 ;;
    --reference) REF=1; RUNS=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
  esac
  shift
done
for t in jq composer php curl; do command -v "$t" >/dev/null || { echo "$t is required" >&2; exit 1; }; done

setup_app() { # setup_app <dir>
  local W="$1"
  composer create-project laravel/laravel "$W" --no-interaction --prefer-dist -q || { echo "create-project failed" >&2; return 1; }
  cp -R "$EVALS/overlay/." "$W/"
  ( cd "$W" && composer require pestphp/pest --dev -W --no-interaction -q \
      && printf '<?php\n\npest()->extend(Tests\\TestCase::class)->in('"'"'Feature'"'"', '"'"'Unit'"'"');\n' > tests/Pest.php \
      && rm -f tests/Feature/ExampleTest.php tests/Unit/ExampleTest.php ) || { echo "pest install failed" >&2; return 1; }
  ( cd "$W" && php artisan migrate:fresh --seed --force -q ) || { echo "migrate failed" >&2; return 1; }
  ( cd "$W" && git init -q && git config user.email eval@local && git config user.name eval && git add -A && git commit -qm fixture )
  bash "$KIT/install.sh" "$W" >/dev/null 2>&1 || { echo "kit install failed" >&2; return 1; }
  mkdir -p "$W/.claude/tasks" && cp "$EVALS"/tasks/*.md "$W/.claude/tasks/"
  ( cd "$W" && git add -A && git commit -qm "kit + tasks" )
}

serve() { # serve <dir> <port>
  ( cd "$1" && php artisan serve --port="$2" >/dev/null 2>&1 & echo $! > "$1/.eval-server.pid" )
  for _ in $(seq 1 40); do curl -s -o /dev/null "http://127.0.0.1:$2/" && return 0; sleep 1; done
  return 1
}

ALL="[]"
for r in $(seq 1 "$RUNS"); do
  W="$(mktemp -d)/app"
  echo "── run $r/$RUNS — $W"
  setup_app "$W" || exit 1

  START=$(date +%s)
  if [ "$REF" = 1 ]; then
    cp -R "$EVALS/reference/." "$W/"
    for t in "$W"/.claude/tasks/00[1-4]-*.md; do sed -i.bak -E 's/^status:.*/status: done/' "$t" && rm -f "$t.bak"; done
    sed -i.bak -E 's/^status:.*/status: blocked/' "$W"/.claude/tasks/005-*.md && rm -f "$W"/.claude/tasks/005-*.md.bak
  else
    RUNNER=(bash "$W/.claude/hooks/run-tasks.sh" --checkpoint --budget "$BUDGET")
    [ "$DRY" = 1 ] && RUNNER+=(--dry-run)
    (cd "$W" && CLAUDE_PROJECT_DIR="$W" "${RUNNER[@]}")
  fi
  WALL=$(( $(date +%s) - START ))
  if [ "$DRY" = 1 ]; then echo "dry run: harness OK"; exit 0; fi

  ( cd "$W" && php artisan migrate:fresh --seed --force -q )   # a clean, known dataset for scoring
  TESTS="$(cd "$W" && php artisan test >/dev/null 2>&1 && echo pass || echo fail)"
  PORT=$(( 8800 + r )); SERVED=0
  serve "$W" "$PORT" && SERVED=1
  TASKS="[]"
  for c in "$EVALS"/checks/*.sh; do
    ID="$(basename "$c" .sh)"
    ST="$(sed -n '2,/^---/p' "$W"/.claude/tasks/"$ID"-*.md 2>/dev/null | sed -nE 's/^status:[[:space:]]*([a-z]+).*/\1/p' | head -1)"
    if [ "$SERVED" = 1 ] || [ "$ID" = 002 ] || [ "$ID" = 005 ]; then
      WHY="$(cd "$W" && BASE_URL="http://127.0.0.1:$PORT" STATUS="$ST" bash "$c" 2>&1)"; RC=$?
      ( cd "$W" && php artisan migrate:fresh --seed --force -q )   # checks may delete rows
    else WHY="app did not start"; RC=1; fi
    TASKS="$(jq -c --arg id "$ID" --arg st "${ST:-?}" --argjson ok "$([ "$RC" = 0 ] && echo true || echo false)" --arg why "${WHY:-ok}" \
      '. + [{id:$id, status:$st, pass:$ok, detail:$why}]' <<<"$TASKS")"
    printf '   %-4s %-8s %-5s %s\n' "$ID" "${ST:-?}" "$([ "$RC" = 0 ] && echo pass || echo FAIL)" "${WHY:-}"
  done
  [ -f "$W/.eval-server.pid" ] && kill "$(cat "$W/.eval-server.pid")" 2>/dev/null
  pkill -f "artisan serve --port=$PORT" 2>/dev/null || true
  M="$W/.claude/.cache/metrics.jsonl"
  COST=0; FP=null   # no metrics file (e.g. a reference run): jq would print a value AND fail
  if [ -s "$M" ]; then
  COST="$(jq -s '[.[] | select(.event=="run") | (.cost_usd|tonumber)] | add // 0' "$M" 2>/dev/null)" || COST=0
  FP="$(jq -s '[.[] | select(.event=="verdict" and (.round|tostring)=="1" and .result!="SKIPPED")] as $v
              | if ($v|length)==0 then null else (([$v[] | select(.result|startswith("PASS"))]|length) / ($v|length)) end' "$M" 2>/dev/null)" || FP=null
  fi
  ALL="$(jq -c --argjson t "$TASKS" --arg tests "$TESTS" --argjson cost "${COST:-0}" --argjson s "$WALL" --argjson fp "${FP:-null}" \
    '. + [{tasks:$t, suite:$tests, cost_usd:$cost, seconds:$s, verifier_first_pass:$fp}]' <<<"$ALL")"
  [ "$KEEP" = 1 ] || rm -rf "${W%/app}"
done

SUMMARY="$(jq -c '
  def mean: if length==0 then 0 else add/length end;
  def sd: (mean) as $m | if length<2 then 0 else (map(.-$m|.*.)|add/(length-1)|sqrt) end;
  (map([.tasks[]|select(.pass)]|length)) as $passed | (.[0].tasks|length) as $n
  | { runs: length, tasks: $n,
      pass_rate_mean: (($passed|map(./$n))|mean), pass_rate_sd: (($passed|map(./$n))|sd),
      per_task: ([.[].tasks[]] | group_by(.id) | map({id:.[0].id, passed:(map(select(.pass))|length), of:length})),
      suite_pass: (map(select(.suite=="pass"))|length), cost_mean: (map(.cost_usd)|mean), seconds_mean: (map(.seconds)|mean),
      verifier_first_pass_mean: ([.[].verifier_first_pass|select(.!=null)] | if length==0 then null else mean end) }' <<<"$ALL")"
echo
jq -r '"pass rate \((.pass_rate_mean*100|round))% ± \((.pass_rate_sd*100|round)) over \(.runs) runs · test suite green \(.suite_pass)/\(.runs) · $\(.cost_mean*100|round/100)/run · \(.seconds_mean|round)s/run · verifier first-pass \(if .verifier_first_pass_mean == null then "n/a" else "\(.verifier_first_pass_mean*100|round)%" end)",
       (.per_task[] | "  task \(.id): \(.passed)/\(.of)")' <<<"$SUMMARY"
mkdir -p "$EVALS/results"
OUTF="$EVALS/results/$(date +%Y%m%d-%H%M%S)-v$(cat "$KIT/VERSION")$([ "$REF" = 1 ] && echo -reference).json"
jq -n --arg v "$(cat "$KIT/VERSION")" --argjson s "$SUMMARY" --argjson runs "$ALL" '{version:$v, summary:$s, runs:$runs}' > "$OUTF"
echo "result: $OUTF"
