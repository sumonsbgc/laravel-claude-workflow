#!/usr/bin/env bash
# PreToolUse(Bash): steps that belong to the user, not to Claude.
#
#   git push, gh pr create, gh pr merge     publishing is the user's call; work stays local
#   tasks.sh approve / tasks.sh accept      the user approves drafts and accepts unverified work
#   a shell edit of a task's `status:`      the same thing, done around the helper
#
# A blocking exit (2) wins over allow rules, so a stray `Bash(git push *)` allow in
# settings.local.json doesn't reopen it. Like guard-secrets this is a speed bump, not a
# boundary: a git alias or a script can still push. The user runs these steps in a terminal.
#
#   LARAVEL_WF_ALLOW_PUSH=1  (in the environment Claude Code was started with) -> allow pushing
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
INPUT="$(cat)"
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')"
else
  CMD="$(printf '%s' "$INPUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.stdout.write(JSON.parse(s).tool_input?.command||"")}catch{}})')"
fi
[ -n "$CMD" ] || exit 0

block() { echo "Blocked by laravel-workflow: $1" >&2; exit 2; }

# A heredoc fed to anything but a shell is data (a draft for `tasks.sh new`, a script for python,
# a file for cat), not commands: drop its body. Fed to a bare shell (`bash <<EOF`) it runs, so it stays.
FIRST="${CMD%%$'\n'*}"
HEREDOCS="${FIRST//[^<]/ }"; HEREDOCS="$(printf '%s' "$HEREDOCS" | grep -o '<<' | wc -l | tr -d ' ')"
if [ "$HEREDOCS" = 1 ] && [[ "$FIRST" != *'<<<'* ]] && [[ "$FIRST" =~ \<\<(-?)[[:space:]]*([^[:space:]\;\&\|\<\>\(\)]+) ]]; then
  DASH="${BASH_REMATCH[1]}"
  TAG="$(printf '%s' "${BASH_REMATCH[2]}" | tr -d "\"'\\\\")"
  [[ "$TAG" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || TAG=""
fi
PRE="${FIRST%%<<*}"
[[ "$PRE" == *[\"\'\`\\#]* || "$PRE" == *'$('* ]] && TAG=""
if [ -n "${TAG:-}" ]; then
  read -ra F <<<"$PRE"
  k=0; while [ "$k" -lt "${#F[@]}" ] && [[ "${F[$k]}" == *=* ]]; do k=$((k + 1)); done
  RUNS=0
  if [[ "${F[$k]:-}" =~ ^(.*/)?(bash|sh|zsh|dash|ksh)$ ]]; then
    RUNS=1; for x in "${F[@]:$((k + 1))}"; do [[ "$x" == -* ]] || { RUNS=0; break; }; done   # `bash script.sh <<X` feeds data
  fi
  if [ "$RUNS" = 0 ]; then
    TERMINATED="$(printf '%s\n' "$CMD" | awk -v t="$TAG" -v dash="$DASH" 'NR > 1 { l = $0; if (dash == "-") sub(/^\t+/, "", l); if (l == t) { print "yes"; exit } }')"
    if [ "$TERMINATED" = yes ]; then
      REST="$(printf '%s\n' "$CMD" | awk -v t="$TAG" -v dash="$DASH" 'NR > 1 && !past { l = $0; if (dash == "-") sub(/^\t+/, "", l); if (l == t) past = 1; next } NR > 1 { print }')"
      CMD="$FIRST"${REST:+$'\n'"$REST"}
    fi
  fi
fi

# Quotes and backslashes only change how the shell groups words; drop them so `"git" push`
# and `git\ push` look like what they run.
NORM="$(printf '%s' "$CMD" | tr -d "\"'\\\\")"

if [[ "$NORM" =~ verify\.sh([^A-Za-z0-9_]|$) ]] && [[ "$NORM" == *--baseline* ]]; then
  block "verify.sh --baseline records the current static-analysis findings as accepted. Only the user runs it (in their own terminal, or with ! in the prompt)."
fi

HELPERS="$(wf_helpers "$SELF_DIR")"
push_allowed() {
  [ "${LARAVEL_WF_ALLOW_PUSH:-0}" = 1 ] && return 0
  local transcript last
  transcript="$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)"
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1
  last="$(jq -c 'select(.type == "user" and (.isMeta | not) and (.isSidechain | not) and (.message.content | type) == "string") | .message.content' "$transcript" 2>/dev/null | tail -n 1)"
  [[ "$last" == *'<command-name>/laravel:sync</command-name>'* ]]
}
check_sync_push() {
  push_allowed || block "pushing is the user's call: it runs only in the turn the user started with /laravel:sync (which commits, pulls the stage branch, checks, then pushes), or bash $HELPERS/git-sync.sh push in their own terminal. Finish the work and tell the user it is ready."
}

TASKS_DIR="${LARAVEL_WF_TASKS_DIR:-.claude/tasks}"
WRITES='(^|[[:space:]])(-i[^[:space:]]*|--in-place|tee|python3?|node|perl|ruby)([[:space:]]|$)|>'
if [[ "$NORM" == *status:* ]] && [[ "$NORM" == *"${TASKS_DIR%/}/"* || "$NORM" == *tasks/* ]] && [[ "$NORM" =~ $WRITES ]]; then
  block "a task's status is changed only through tasks.sh (start/close/block); approving a draft or accepting unverified work is the user's step. Tell the user what is ready and ask them to run it."
fi

# Only words in command position count, so `git commit -m "then push"` or an echo that mentions
# tasks.sh is left alone. Wrappers (sudo, env, xargs, timeout, bash script.sh, sh -c ...) keep the
# position open for the word after them.
set -f
while IFS= read -r SEG; do
  read -ra W <<<"$SEG"
  n=${#W[@]}; CP=1; WRAP=0
  for ((i = 0; i < n && CP == 1; i++)); do
    w="${W[$i]}"
    case "$w" in
      git|*/git)
        j=$((i + 1))
        while [ "$j" -lt "$n" ]; do       # skip git's global options to reach the subcommand
          case "${W[$j]}" in
            -C|-c|--git-dir|--work-tree|--namespace|--exec-path) j=$((j + 2)) ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        if [ "${W[$j]:-}" = push ]; then
          block "plain git push skips the stage-branch pull. Push only through the kit: bash $HELPERS/git-sync.sh push (it refuses until the branch contains the stage branch; run git-sync.sh sync first). Without /laravel:sync from the user, pushing is their call."
        fi
        CP=0 ;;
      gh|*/gh)
        if [ "${W[$((i + 1))]:-}" = pr ] && [[ "${W[$((i + 2))]:-}" =~ ^(create|merge)$ ]] && [ "${LARAVEL_WF_ALLOW_PUSH:-0}" != 1 ]; then
          block "opening or merging a pull request publishes the branch — that is the user's call. Tell the user the work is ready instead."
        fi
        CP=0 ;;
      *git-sync.sh)
        [ "${W[$((i + 1))]:-}" = push ] && check_sync_push
        CP=0 ;;
      *tasks.sh|\$*)
        [[ "$w" == \$* ]] && [ "${W[$((i + 1))]:-}" = push ] && check_sync_push
        if [[ "${W[$((i + 1))]:-}" =~ ^(approve|accept)$ ]]; then
          block "tasks.sh ${W[$((i + 1))]} is the user's step: they approve drafts after reading them, and accept work whose [browser] criteria nobody could check. Tell the user which task is waiting and ask them to run: bash $(wf_helpers "$SELF_DIR")/tasks.sh ${W[$((i + 1))]} <id>"
        fi
        CP=0 ;;
      sudo|env|xargs|nice|timeout|nohup|*/env) WRAP=1 ;;   # their option values look like words: keep scanning
      command|exec|time|builtin|then|do|else|if|while|until|!|source|.) ;;
      bash|sh|zsh|dash|ksh|*/bash|*/sh|*/zsh) ;;
      -*|[0-9]*|*=*) ;;                   # options, timeout's duration, VAR=value
      *) [ "$WRAP" = 1 ] || CP=0 ;;
    esac
  done
done < <(printf '%s\n' "$NORM" | sed 's/[;&|()]/\n/g')
set +f
exit 0
