#!/bin/sh
# Portable stop policy. The adapter maps a block to each runtime's continuation path.
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INPUT=$(cat 2>/dev/null || true)
EVENT=$(printf '%s' "$INPUT" | "$SCRIPT_DIR/prepare-event.sh" stop)
STATUS=$?
[ "$STATUS" -eq 4 ] && exit 0
[ "$STATUS" -eq 0 ] || exit 3

command -v jq >/dev/null 2>&1 || exit 3
CWD=$(printf '%s' "$EVENT" | jq -r '.cwd') || exit 3
LOOP_ACTIVE=$(printf '%s' "$EVENT" | jq -r '.stop.verification_loop_active') || exit 3
REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")

CHECK_CMD=${HARNESS_CHECK:-}
if [ -z "$CHECK_CMD" ] && [ -f "$REPO_ROOT/.harness/check" ]; then
  CHECK_CMD=$(head -5 "$REPO_ROOT/.harness/check" | grep -v '^#' | head -1)
fi
[ -n "$CHECK_CMD" ] || exit 0

if [ "$LOOP_ACTIVE" = "true" ]; then
  echo "stop-verify-gate: check still failing after one continuation; allowing stop for human review. Do not report this work as done." >&2
  exit 0
fi

OUTPUT=$(cd "$REPO_ROOT" && eval "$CHECK_CMD" 2>&1)
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
  {
    echo "BLOCKED by stop-verify-gate: the check is failing; the task is not done."
    echo "Check command: $CHECK_CMD (exit $STATUS)"
    echo "Last 40 lines:"
    printf '%s\n' "$OUTPUT" | tail -40
    echo "Fix the failure or report the blocker honestly."
  } >&2
  exit 2
fi

exit 0
