#!/usr/bin/env bash
# Install the Laravel agentic workflow into a project (default) or into ~/.claude (--global).
#
#   ./install.sh /path/to/my-laravel-app
#   ./install.sh .                 # from inside the project
#   ./install.sh --global          # agents/commands/skills/hooks for every project
#   ./install.sh . --dry-run
#   ./install.sh /path/to/app --uninstall   remove the kit's files and hook entries
#
# Files this kit owns are namespaced (agents/{laravel,blade}-*, commands/laravel/,
# skills/{laravel-conventions,blade-conventions,php-conventions}, hooks/*.sh) and are
# overwritten on reinstall. Nothing else is touched; an existing settings.json is merged,
# not replaced, and backed up first.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""; GLOBAL=0; DRY=0; FORCE=0; UNINSTALL=0
VERSION="$(cat "$KIT/VERSION" 2>/dev/null || echo dev)"
for a in "$@"; do
  case "$a" in
    --global) GLOBAL=1 ;;
    --dry-run) DRY=1 ;;
    --force) FORCE=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
    *) TARGET="$a" ;;
  esac
done

say()  { printf '  %s\n' "$*"; }
run()  { if [ "$DRY" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else eval "$*"; fi; }

if [ "$GLOBAL" = 1 ]; then
  DEST="$HOME/.claude"
  HOOK_BASE="\$HOME/.claude/hooks"
  [ "$UNINSTALL" = 1 ] || printf '\nInstalling laravel-workflow globally into %s\n\n' "$DEST"
else
  TARGET="${TARGET:-$PWD}"
  [ -d "$TARGET" ] || { echo "No such directory: $TARGET" >&2; exit 1; }
  TARGET="$(cd "$TARGET" && pwd)"
  [ "$TARGET" = "$KIT" ] && { echo "Pass the path of the Laravel project to install into (or --global)." >&2; exit 1; }
  if [ "$UNINSTALL" = 0 ] && { [ ! -f "$TARGET/artisan" ] || ! grep -q '"laravel/framework"' "$TARGET/composer.json" 2>/dev/null; }; then
    if [ "$FORCE" = 1 ]; then say "warning: $TARGET does not look like a Laravel project (continuing, --force)"
    else echo "$TARGET has no artisan / laravel/framework in composer.json. Re-run with --force if that's expected." >&2; exit 1; fi
  fi
  DEST="$TARGET/.claude"
  HOOK_BASE="\$CLAUDE_PROJECT_DIR/.claude/hooks"
  [ "$UNINSTALL" = 1 ] || printf '\nInstalling laravel-workflow into %s\n\n' "$TARGET"
fi

# Kit-owned hook commands, matched by script name: dropped before merging (so upgrades never
# stack duplicates) and removed on uninstall.
KIT_HOOKS_RE='\.claude/hooks/(session-context|guard-php|guard-blade|guard-styles|guard-editor|format|post-edit|bash-guard|guard-secrets|verify)\.sh'
# Permission rules earlier kit versions shipped and this one deliberately removed. A union merge
# would keep them forever, so they're dropped from the existing settings on every install.
RETIRED='["Read(//home/**)","Bash(npm run dev:*)","Bash(npm run build:*)","Bash(vendor/bin/phpstan:*)","Bash(php artisan migrate --pretend:*)","Bash(php artisan config:clear:*)","Bash(php artisan view:clear:*)","Bash(php artisan migrate:status:*)"]'
strip_kit() { # stdin settings JSON -> without the kit's hook entries and retired permission rules
  jq --arg re "$KIT_HOOKS_RE" --argjson retired "$RETIRED" '
    (if .hooks then
      .hooks |= (with_entries(.value |= (map(.hooks |= map(select((.command // "") | test($re) | not)))
                                         | map(select((.hooks | length) > 0))))
                 | with_entries(select((.value | length) > 0)))
    else . end)
    | (if .permissions.allow then .permissions.allow -= $retired else . end)
    # deny rules are never removed (they only add protection, and some may belong to the user)'
}

if [ "$UNINSTALL" = 1 ]; then
  printf '\nRemoving laravel-workflow from %s\n\n' "$DEST"
  run "rm -rf '$DEST/commands/laravel' '$DEST/skills/laravel-conventions' '$DEST/skills/blade-conventions' '$DEST/skills/php-conventions'"
  run "rm -f '$DEST/agents/'laravel-*.md '$DEST/agents/'blade-*.md '$DEST/laravel-workflow.version' '$DEST/verify.playwright.config.mjs'"
  for h in _lib stack tasks session-context guard-php guard-blade guard-styles guard-editor format post-edit bash-guard guard-secrets verify verify-browser run-tasks; do
    run "rm -f '$DEST/hooks/$h.sh'"
  done
  if [ -f "$DEST/settings.json" ] && command -v jq >/dev/null 2>&1; then
    if [ "$DRY" = 0 ]; then
      BAK="$DEST/settings.json.bak.$(date +%s)"
      cp "$DEST/settings.json" "$BAK"
      strip_kit < "$BAK" > "$DEST/settings.json.tmp" 2>/dev/null && mv "$DEST/settings.json.tmp" "$DEST/settings.json"
    fi
    say "settings: kit hooks removed (backup written alongside; your own permissions left as they are)"
  else
    say "settings: remove the laravel-workflow hook entries from $DEST/settings.json by hand"
  fi
  say "kept: tasks/, .claude/project-context.md, CLAUDE.md — they are your project's, not the kit's"
  exit 0
fi

# ---- files -------------------------------------------------------------------
run "mkdir -p '$DEST/agents' '$DEST/commands' '$DEST/skills' '$DEST/hooks'"
run "cp '$KIT/.claude/agents/'laravel-*.md '$KIT/.claude/agents/'blade-*.md '$DEST/agents/'"
run "rm -rf '$DEST/commands/laravel'"
run "cp -R '$KIT/.claude/commands/laravel' '$DEST/commands/'"
for s in laravel-conventions blade-conventions php-conventions; do
  run "rm -rf '$DEST/skills/$s'"
  run "cp -R '$KIT/.claude/skills/$s' '$DEST/skills/'"
done
run "cp '$KIT/.claude/hooks/'*.sh '$DEST/hooks/'"
run "cp '$KIT/.claude/verify.playwright.config.mjs' '$DEST/'"
if [ "$DRY" = 0 ]; then printf '%s\n' "$VERSION" > "$DEST/laravel-workflow.version"; fi
run "mkdir -p '$DEST/templates'"
run "cp '$KIT/templates/'*.md '$DEST/templates/'"
run "chmod +x '$DEST/hooks/'*.sh"
say "agents:   $(ls "$KIT/.claude/agents" | wc -l | tr -d ' ') files"
say "commands: /laravel:$(ls "$KIT/.claude/commands/laravel" | sed 's/\.md$//' | tr '\n' ' ' | sed 's/ /, \/laravel:/g; s/, \/laravel:$//')"
say "skills:   laravel-conventions, blade-conventions, php-conventions (+ $(cat "$KIT/.claude/skills/"*/references/* /dev/null | wc -l | tr -d ' ') lines of references)"
say "hooks:    session-context, post-edit (guard-php, guard-blade, guard-styles, guard-editor, format), bash-guard, guard-secrets, verify"
say "helpers:  stack.sh (detection, cached), tasks.sh (task bookkeeping), run-tasks.sh (headless runner), verify-browser.sh"
say "version:  $VERSION"

# ---- settings.json -----------------------------------------------------------
NEW_SETTINGS="$(sed "s|\$CLAUDE_PROJECT_DIR/.claude/hooks|$(printf '%s' "$HOOK_BASE" | sed 's/[&|]/\\&/g')|g" "$KIT/.claude/settings.json")"
if [ "$GLOBAL" = 1 ]; then
  # Helpers live in ~/.claude: the commands Claude runs are `bash ~/.claude/hooks/…`.
  NEW_SETTINGS="$(printf '%s' "$NEW_SETTINGS" | sed 's|Bash(bash \.claude/hooks/|Bash(bash ~/.claude/hooks/|g')"
fi
SETTINGS="$DEST/settings.json"
if [ ! -f "$SETTINGS" ]; then
  if [ "$DRY" = 1 ]; then say "[dry-run] write $SETTINGS"; else printf '%s\n' "$NEW_SETTINGS" > "$SETTINGS"; fi
  say "settings: written"
elif command -v jq >/dev/null 2>&1; then
  OLD_CLEAN="$(strip_kit < "$SETTINGS")"
  MERGED="$(printf '%s' "$NEW_SETTINGS" | jq -s '
    .[0] as $a | .[1] as $b |
    ($a * $b)
    | .permissions.allow = ((($a.permissions.allow // []) + ($b.permissions.allow // [])) | unique)
    | .permissions.deny  = ((($a.permissions.deny  // []) + ($b.permissions.deny  // [])) | unique)
    | .hooks = (
        ($a.hooks // {}) as $ah | ($b.hooks // {}) as $bh |
        reduce ((($ah | keys) + ($bh | keys)) | unique)[] as $k ({};
          .[$k] = (($ah[$k] // []) + ($bh[$k] // [])
                   | reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end))))
  ' <(printf '%s' "$OLD_CLEAN") -)"
  if [ "$DRY" = 1 ]; then say "[dry-run] merge into $SETTINGS"; else
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
    printf '%s\n' "$MERGED" > "$SETTINGS"
  fi
  say "settings: merged (backup written alongside)"
else
  if [ "$DRY" = 0 ]; then printf '%s\n' "$NEW_SETTINGS" > "$DEST/settings.laravel-workflow.json"; fi
  say "settings: jq not found — wrote settings.laravel-workflow.json; merge its hooks/permissions in by hand"
fi

# ---- gitignore ---------------------------------------------------------------
if [ "$GLOBAL" = 0 ]; then
  GI="$TARGET/.gitignore"
  if [ ! -f "$GI" ] || ! grep -q '^\.claude/\.cache/' "$GI"; then
    if [ "$DRY" = 0 ]; then printf '\n.claude/.cache/\n' >> "$GI"; fi
    say "gitignore: added .claude/.cache/"
  fi
fi

# ---- static-analysis baseline -------------------------------------------------
# Record findings that already exist, so the Stop hook (analyse mode) only fails on new ones.
# Done here, by you — the agent is not allowed to baseline its own findings.
if [ "$GLOBAL" = 0 ] && [ "$DRY" = 0 ] && [ -x "$TARGET/vendor/bin/phpstan" ]; then
  say "baseline: running static analysis once to record pre-existing findings…"
  say "$(CLAUDE_PROJECT_DIR="$TARGET" bash "$DEST/hooks/verify.sh" --baseline 2>&1 | tail -1)"
fi

cat <<'NEXT'

Done. In that project, start Claude Code and run:

    /laravel:setup                       detect the stack, seed the project memory (once)

Plan, approve, build:

    /laravel:write-task <what you want>  planner (Opus) writes draft task files
    bash .claude/hooks/tasks.sh approve all        after you've read them
    /laravel:task                        build the next task (Sonnet)
    /laravel:feature <id>                force the full phased build on one task

Long batches — each task in a fresh session, one commit per task on its own branch:

    bash .claude/hooks/run-tasks.sh --checkpoint

Around the work:  /laravel:test  /laravel:review  /laravel:audit  /laravel:ship
Numbers:          bash .claude/hooks/tasks.sh stats

NEXT
