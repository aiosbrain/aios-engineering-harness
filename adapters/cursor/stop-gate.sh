#!/bin/sh
# Cursor `stop` hook wrapper.
#
# Cursor's stop hook does not block via exit code — it continues the agent when the
# hook returns {"followup_message": "..."} on stdout. So instead of letting the raw
# exit-2 flow through (as pre_command/pre_edit do), run the portable stop-verify-gate
# and, if it blocks, emit a followup_message telling Cursor to keep going until the
# repository verification gate (`.harness/check`) passes. Always exits 0.
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INPUT=$(cat 2>/dev/null || true)

OUT=$(printf '%s' "$INPUT" | "$SCRIPT_DIR/../run-hook.sh" cursor stop stop-verify-gate.sh 2>&1)
STATUS=$?

if [ "$STATUS" -eq 2 ]; then
  # Blocked: hand the gate's reason back to Cursor as a continuation prompt.
  msg=$(printf '%s' "$OUT" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g')
  [ -n "$msg" ] || msg="Repository verification gate failed; resolve it before stopping."
  printf '{"followup_message":"%s"}\n' "$msg"
fi
exit 0
