#!/usr/bin/env bash
# guard-destructive.sh — PreToolUse hook (Bash)
#
# Blocks catastrophic shell commands: recursive force-delete outside the repo,
# force-push / hard-reset on protected branches, history rewrites, disk-level ops.
# Curated from: disler/claude-code-hooks-mastery patterns + Anthropic's
# destructive-op confirmation practice. AM patterns: C4, B6.
#
# "Block" here means: the agent is told why and asked to get explicit human
# approval — it does NOT mean the human can't run the command themselves.
#
# Contract: JSON on stdin { "tool_input": { "command": "..." } }.
# Exit 0 = allow. Exit 2 + stderr = BLOCK.
# Escape hatch: HARNESS_ALLOW_DESTRUCTIVE=1 (set it for one command, not for life).

set -euo pipefail

[ "${HARNESS_ALLOW_DESTRUCTIVE:-0}" = "1" ] && exit 0

STDIN_JSON=$(cat 2>/dev/null || true)
[ -z "$STDIN_JSON" ] && exit 0
command -v jq >/dev/null 2>&1 || { echo "guard-destructive: jq not found; scan skipped" >&2; exit 0; }

CMD=$(printf '%s' "$STDIN_JSON" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

PROTECTED_BRANCHES="${HARNESS_PROTECTED_BRANCHES:-main|master|production|release}"

block() {
  { echo "BLOCKED by guard-destructive: $1"; echo "Command: $CMD"; echo "$2"; } >&2
  exit 2
}

# 1. rm -rf against root-ish / home / parent paths (allow repo-relative rm -rf)
if printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*f[a-zA-Z]*|-[a-zA-Z]*f[a-zA-Z]*[rR][a-zA-Z]*)[[:space:]]'; then
  if printf '%s' "$CMD" | grep -qE 'rm[[:space:]]+-[a-zA-Z]*[[:space:]]+("?/([^/]|$)|"?~|\$HOME|\.\.)'; then
    block "recursive force-delete outside the repository" \
      "rm -rf against /, ~, \$HOME, or .. requires explicit human approval."
  fi
fi

# 2. Force-push to protected branches (allow --force-with-lease to feature branches)
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+push[^;|&]*(--force([[:space:]]|$)|-f([[:space:]]|$))' &&
   printf '%s' "$CMD" | grep -qE "(${PROTECTED_BRANCHES})"; then
  block "force-push to a protected branch" \
    "Force-pushing ${PROTECTED_BRANCHES//|/, } rewrites shared history. Get explicit approval."
fi

# 3. Hard reset / branch deletion on protected branches
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+(reset[[:space:]]+--hard|branch[[:space:]]+-D)[^;|&]*' &&
   printf '%s' "$CMD" | grep -qE "(${PROTECTED_BRANCHES})"; then
  block "hard reset / delete on a protected branch" \
    "This discards commits on a shared branch. Get explicit approval."
fi

# 4. Repo-wide history rewrite / reflog destruction
if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+(filter-branch|filter-repo|reflog[[:space:]]+expire[^;|&]*--expire=now)'; then
  block "git history rewrite" "History rewrites are unrecoverable for collaborators. Get explicit approval."
fi

# 5. Disk / device level operations
if printf '%s' "$CMD" | grep -qE '(^|[;&|[:space:]])(mkfs(\.[a-z0-9]+)?|dd[[:space:]]+[^;|&]*of=/dev/|shred[[:space:]]|diskutil[[:space:]]+erase)'; then
  block "disk-level destructive operation" "Device-level writes require a human at the keyboard."
fi

# 6. Destructive SQL piped straight into a database CLI
if printf '%s' "$CMD" | grep -qiE '(DROP[[:space:]]+(TABLE|DATABASE|SCHEMA)|TRUNCATE[[:space:]]+TABLE)' &&
   printf '%s' "$CMD" | grep -qE '(psql|mysql|sqlite3|mongosh)'; then
  block "destructive SQL against a live database" \
    "DROP/TRUNCATE through a DB CLI requires explicit approval (and probably a migration instead)."
fi

exit 0
