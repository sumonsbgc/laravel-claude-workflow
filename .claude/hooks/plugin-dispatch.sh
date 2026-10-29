#!/usr/bin/env bash
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="${1:-}"
[[ "$NAME" =~ ^[a-z-]+$ ]] && [ -f "$SELF_DIR/$NAME.sh" ] || exit 0
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
case "$NAME" in
  guard-secrets|guard-owner|guard-read|guard-comments|bash-guard|allow-helpers) exec bash "$SELF_DIR/$NAME.sh" ;;
esac
registered_by_project() {
  local f
  for f in "$ROOT/.claude/settings.json" "$ROOT/.claude/settings.local.json"; do
    [ -f "$f" ] && grep -qF "/.claude/hooks/$NAME.sh" "$f" && return 0
  done
  return 1
}
if [ "$ROOT/.claude/hooks" != "$SELF_DIR" ] && [ -f "$ROOT/.claude/hooks/$NAME.sh" ] && registered_by_project; then
  if [ "$NAME" = session-context ]; then
    . "$SELF_DIR/_lib.sh"
    wf_context SessionStart "laravel-workflow is installed twice in this project: as a plugin and as project files (.claude/hooks, .claude/commands/laravel, .claude/agents/laravel-* and blade-*). The project files are in use. Ask the user to keep one: remove the project files with install.sh --uninstall, or disable the plugin."
  fi
  exit 0
fi
exec bash "$SELF_DIR/$NAME.sh"
