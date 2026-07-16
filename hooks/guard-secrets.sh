#!/usr/bin/env bash
# guard-secrets.sh — PreToolUse hook (Write|Edit|MultiEdit)
#
# Blocks any file write whose content matches a known secret pattern.
# Curated from: AIOS toolkit team-ops-guard.sh. AM pattern: C4 (hooks for what
# must happen every time). Enforcement, not suggestion.
#
# Contract (Claude Code): JSON event on stdin
#   { "tool_name": "...", "tool_input": { "file_path": "...", "content"/"new_string": "..." } }
# Exit 0 = allow. Exit 2 + stderr = BLOCK (any other non-zero is a non-blocking error).
#
# Patterns live in secret-patterns.txt beside this script (one extended-regex per
# line, # comments allowed) so teams extend them without editing the hook.

set -euo pipefail

STDIN_JSON=$(cat 2>/dev/null || true)
[ -z "$STDIN_JSON" ] && exit 0

if ! command -v jq >/dev/null 2>&1; then
  # No jq → we cannot parse safely; fail open but say so once on stderr (exit 0 = allow).
  echo "guard-secrets: jq not found; secret scan skipped" >&2
  exit 0
fi

TOOL_INPUT=$(printf '%s' "$STDIN_JSON" | jq -c '.tool_input // empty' 2>/dev/null || true)
[ -z "$TOOL_INPUT" ] && exit 0

FILE_PATH=$(printf '%s' "$TOOL_INPUT" | jq -r '.file_path // .path // empty' 2>/dev/null || true)
CONTENT=$(printf '%s' "$TOOL_INPUT" | jq -r '.content // .new_string // empty' 2>/dev/null || true)
[ -z "$CONTENT" ] && exit 0

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATTERNS_FILE="$HOOK_DIR/secret-patterns.txt"

PATTERNS=()
if [ -f "$PATTERNS_FILE" ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    PATTERNS+=("$line")
  done < "$PATTERNS_FILE"
else
  PATTERNS=(
    "AKIA[0-9A-Z]{16}"
    "-----BEGIN (RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
    "gh[ps]_[A-Za-z0-9_]{36,}"
    "xox[bporas]-[A-Za-z0-9-]+"
    "sk-[A-Za-z0-9_-]{40,}"
    "AIza[0-9A-Za-z_-]{35}"
  )
fi

for pattern in "${PATTERNS[@]}"; do
  # `--` so patterns beginning with `-` (e.g. PEM headers) aren't read as grep options
  if printf '%s' "$CONTENT" | grep -qE -- "$pattern" 2>/dev/null; then
    {
      echo "BLOCKED by guard-secrets: potential secret detected in ${FILE_PATH:-<unknown>}"
      echo "Pattern matched: $pattern"
      echo "Remove the secret (use an env var / secret manager reference) before writing."
    } >&2
    exit 2
  fi
done

exit 0
