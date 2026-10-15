#!/usr/bin/env bash
# PostToolUse(Edit|Write), via post-edit.sh: the kit rule for Post/Page modules is the Gutenberg
# block editor (@wordpress/block-editor) — never CKEditor, TinyMCE, Summernote, Quill or Trix.
# Warns when one of those appears in Post/Page/News/Article code, or is added to package.json.
# See .claude/skills/blade-conventions/references/block-editor.md
#   LARAVEL_WF_EDITOR_GUARD=off  -> disable
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
[ "${LARAVEL_WF_EDITOR_GUARD:-on}" = off ] && exit 0
[ -f "$ROOT/artisan" ] || exit 0
. "$SELF_DIR/_lib.sh"
if [ -n "${LARAVEL_WF_FILE:-}" ]; then FILE="$LARAVEL_WF_FILE"; else FILE="$(wf_file_from_input "$(cat)")"; fi
[ -n "$FILE" ] && [ -f "$FILE" ] || exit 0
REL="${FILE#$ROOT/}"
case "$REL" in vendor/*|node_modules/*|public/build/*|storage/*) exit 0 ;; esac

EDITORS='ckeditor|@ckeditor/|ClassicEditor|tinymce|tinyMCE|summernote|quill|Quill\(|trix-editor|"trix"'
HIT=""
case "$REL" in
  package.json)
    grep -qiE "\"(ckeditor[^\"]*|@ckeditor/[^\"]+|tinymce|@tinymce/[^\"]+|summernote|quill|trix)\"[[:space:]]*:" "$FILE" && HIT="package.json adds a classic rich-text editor" ;;
  *.blade.php|*.js|*.ts|*.jsx|*.tsx|*.php)
    # Only Post/Page-like content: the path or the file names a post, page, article or news body.
    if printf '%s' "$REL" | grep -qiE '(post|page|news|article|blog|content)' || grep -qiE '(name="(content|body)"|\$post|\$page|\$article|\$news)' "$FILE"; then
      grep -qiE "$EDITORS" "$FILE" && HIT="$REL wires a classic rich-text editor into Post/Page content"
    fi ;;
esac
[ -n "$HIT" ] || exit 0

wf_metric guard guard editor file "$REL" level warn
TEXT="Editor rule — advisory for $REL:
  - $HIT. This kit's rule: Post/Page content uses the Gutenberg block editor (@wordpress/block-editor as a Vite React island, content stored as block grammar, sanitized content_html for rendering). See blade-conventions/references/block-editor.md. Only keep a classic editor if the user explicitly asked for it for this module."
if [ "${LARAVEL_WF_RAW:-0}" = 1 ]; then printf '%s\n' "$TEXT"; else wf_context PostToolUse "$TEXT"; fi
exit 0
