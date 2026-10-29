#!/usr/bin/env bash
set -uo pipefail
[ "${LARAVEL_WF_SECRETS_GUARD:-on}" = off ] && exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_lib.sh"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
FILE="$(wf_file_from_input "$(cat)")"
[ -n "$FILE" ] || exit 0
B="$(basename "$FILE")"
is_secret_path() {
  case "$B" in
    .env.example|.env.sample|.env.template|.env.dist) return 1 ;;
    .env|.env.*|*.pem|*.key|auth.json|id_rsa|id_rsa.*|id_ed25519|id_ed25519.*|id_ecdsa|id_ecdsa.*) return 0 ;;
  esac
  case "$FILE" in
    "$ROOT"/storage/*|storage/*|./storage/*) return 0 ;;
    "$HOME"/.ssh/*|"$HOME"/.aws/*|*/.ssh/*|*/.aws/*) return 0 ;;
  esac
  return 1
}
is_secret_path || exit 0
wf_metric guard guard read level block
echo "Blocked by laravel-workflow: $B is a secret file (env file, private or Passport key, composer auth.json, or anything under storage/), and secrets stay out of the transcript. For variable names, read .env.example. For errors, use Boost's last-error/read-log-entries tools if installed, or ask the user." >&2
exit 2
