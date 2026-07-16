#!/usr/bin/env bash
# stop-verify-gate.sh — Stop hook
#
# The leash-lengthener: the agent cannot declare a session "done" while the
# repo's check fails. This is the strongest rung of the AM B2 ladder
# ("a stop hook that blocks until the check passes") — it converts a session
# you watch into one you can walk away from. AM patterns: B2, C4.
#
# Configure the check (first match wins):
#   1. $HARNESS_CHECK              — a shell command, e.g. "make lint && make test"
#   2. .harness/check              — a file whose contents are the command
#   If neither exists, the gate is OFF (exit 0) — opt-in by design.
#
# Contract (Claude Code Stop hook): JSON on stdin includes
#   { "stop_hook_active": true } when the agent is already continuing because of
#   a previous Stop-hook block. We allow the stop in that case after one more
#   failed attempt would loop forever — the transcript already contains the
#   failure output for the human.
# Exit 0 = allow stop. Exit 2 + stderr = block stop, feed stderr to the agent.

set -uo pipefail

STDIN_JSON=$(cat 2>/dev/null || true)

CHECK_CMD="${HARNESS_CHECK:-}"
if [ -z "$CHECK_CMD" ] && [ -f ".harness/check" ]; then
  CHECK_CMD=$(head -5 ".harness/check" | grep -v '^#' | head -1)
fi
[ -z "$CHECK_CMD" ] && exit 0   # no gate configured

# Loop protection: if we already blocked once this stop-cycle, let the human decide.
if command -v jq >/dev/null 2>&1 && [ -n "$STDIN_JSON" ]; then
  ACTIVE=$(printf '%s' "$STDIN_JSON" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)
  if [ "$ACTIVE" = "true" ]; then
    echo "stop-verify-gate: check still failing after a blocked stop — allowing stop so a human can look. Do not report this work as done." >&2
    exit 0
  fi
fi

OUTPUT=$(eval "$CHECK_CMD" 2>&1)
STATUS=$?

if [ $STATUS -ne 0 ]; then
  {
    echo "BLOCKED by stop-verify-gate: the check is failing — the task is not done."
    echo "Check command: $CHECK_CMD (exit $STATUS)"
    echo "--- last 40 lines of output ---"
    printf '%s\n' "$OUTPUT" | tail -40
    echo "--- end output ---"
    echo "Fix the failure (or explicitly tell the human you are blocked and why)."
  } >&2
  exit 2
fi

exit 0
