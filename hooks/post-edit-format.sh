#!/usr/bin/env bash
# post-edit-format.sh — PostToolUse hook (Write|Edit|MultiEdit)
#
# Auto-formats the file the agent just wrote, using whatever formatter the repo
# already has. Deterministic hygiene the agent never has to think about — and
# the human never has to nag about. Curated from: Boris Cherny (hooks
# auto-format after edits). AM pattern: C4.
#
# NEVER blocks: always exits 0. Unknown file type or missing formatter = no-op.

set -uo pipefail

STDIN_JSON=$(cat 2>/dev/null || true)
[ -z "$STDIN_JSON" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

FILE_PATH=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
[ -n "$FILE_PATH" ] && [ -f "$FILE_PATH" ] || exit 0

has_local() { [ -x "./node_modules/.bin/$1" ]; }
run_prettier() {
  if has_local prettier; then ./node_modules/.bin/prettier --write "$FILE_PATH" >/dev/null 2>&1
  elif command -v prettier >/dev/null 2>&1; then prettier --write "$FILE_PATH" >/dev/null 2>&1
  fi
}

case "$FILE_PATH" in
  *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.json|*.css|*.scss|*.md|*.html|*.vue|*.svelte|*.yaml|*.yml)
    run_prettier || true
    ;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then ruff format "$FILE_PATH" >/dev/null 2>&1 || true
    elif command -v black >/dev/null 2>&1; then black -q "$FILE_PATH" >/dev/null 2>&1 || true
    fi
    ;;
  *.php)
    if [ -x "./vendor/bin/pint" ]; then ./vendor/bin/pint "$FILE_PATH" >/dev/null 2>&1 || true
    elif [ -x "./vendor/bin/php-cs-fixer" ]; then ./vendor/bin/php-cs-fixer fix "$FILE_PATH" >/dev/null 2>&1 || true
    fi
    ;;
  *.go)
    command -v gofmt >/dev/null 2>&1 && gofmt -w "$FILE_PATH" >/dev/null 2>&1 || true
    ;;
  *.rs)
    command -v rustfmt >/dev/null 2>&1 && rustfmt "$FILE_PATH" >/dev/null 2>&1 || true
    ;;
esac

exit 0
