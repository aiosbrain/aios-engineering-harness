#!/usr/bin/env bash
# guard-protected-paths.sh — PreToolUse hook (Write|Edit|MultiEdit)
#
# Blocks agent edits to paths that must only change through a deliberate human
# action or a dedicated tool: env files, lockfiles, migrations, CI workflows,
# generated/vendored code. "Never edit .env" in a prompt is a request; this
# hook makes it a guarantee. AM pattern: C4.
#
# Deny patterns live in protected-paths.txt beside this script (one glob-ish
# extended regex per line, matched against the path relative to CWD and the
# absolute path). Repos can override with their own file at
# .harness/protected-paths.txt (repo file REPLACES the default list).
#
# Contract: JSON on stdin. Exit 0 = allow. Exit 2 + stderr = BLOCK.

set -euo pipefail

STDIN_JSON=$(cat 2>/dev/null || true)
[ -z "$STDIN_JSON" ] && exit 0
command -v jq >/dev/null 2>&1 || { echo "guard-protected-paths: jq not found; scan skipped" >&2; exit 0; }

FILE_PATH=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)
[ -z "$FILE_PATH" ] && exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_LIST="$(pwd)/.harness/protected-paths.txt"
DEFAULT_LIST="$HOOK_DIR/protected-paths.txt"
LIST_FILE="$DEFAULT_LIST"
[ -f "$REPO_LIST" ] && LIST_FILE="$REPO_LIST"

PATTERNS=()
if [ -f "$LIST_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    PATTERNS+=("$line")
  done < "$LIST_FILE"
else
  PATTERNS=('(^|/)\.env($|\.)' '(^|/)node_modules/' '(^|/)vendor/' '\.lock$' '(^|/)migrations?/')
fi

for pattern in "${PATTERNS[@]}"; do
  if printf '%s' "$FILE_PATH" | grep -qE "$pattern" 2>/dev/null; then
    {
      echo "BLOCKED by guard-protected-paths: $FILE_PATH matches protected pattern '$pattern'"
      echo "This path only changes through a deliberate human action or its dedicated tool"
      echo "(migration generator, package manager, CI owner). Ask the human, or update"
      echo "$LIST_FILE if this protection is wrong for the repo."
    } >&2
    exit 2
  fi
done

exit 0
