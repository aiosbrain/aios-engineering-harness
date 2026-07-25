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

command -v jq >/dev/null 2>&1 || {
  echo "cursor stop gate: jq not found" >&2
  exit 3
}

NATIVE_STATUS=$(printf '%s' "$INPUT" | jq -r '.status // ""' 2>/dev/null || true)
case "$NATIVE_STATUS" in
  aborted|error)
    printf '{}\n'
    exit 0
    ;;
esac

OUT=$(printf '%s' "$INPUT" | "$SCRIPT_DIR/../run-hook.sh" cursor stop stop-verify-gate.sh 2>&1)
STATUS=$?

if [ "$STATUS" -eq 2 ]; then
  # Blocked: hand the gate's reason back to Cursor as a continuation prompt.
  [ -n "$OUT" ] || OUT="Repository verification gate failed; resolve it before stopping."
  printf '%s' "$OUT" | jq -Rs '{followup_message: .}'
else
  printf '{}\n'
fi
exit 0
