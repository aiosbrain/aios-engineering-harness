#!/bin/sh
# Usage: run-hook.sh <claude-code|codex> <event> <policy-script>
set -u

RUNTIME=${1:-}
EVENT=${2:-}
POLICY=${3:-}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

case "$RUNTIME" in
  claude-code) NORMALIZER="$SCRIPT_DIR/claude-code/normalize.sh" ;;
  codex) NORMALIZER="$SCRIPT_DIR/codex/normalize.sh" ;;
  *) echo "adapter: unsupported runtime '$RUNTIME'" >&2; exit 3 ;;
esac

case "$POLICY" in
  guard-secrets.sh|guard-protected-paths.sh|guard-destructive.sh|post-edit-format.sh|stop-verify-gate.sh) ;;
  *) echo "adapter: unsupported policy '$POLICY'" >&2; exit 3 ;;
esac

INPUT=$(cat 2>/dev/null || true)
NORMALIZED=$(printf '%s' "$INPUT" | "$NORMALIZER" "$EVENT")
STATUS=$?

if [ "$STATUS" -ne 0 ]; then
  if [ "$POLICY" = "post-edit-format.sh" ]; then exit 0; fi
  echo "BLOCKED by harness adapter: payload normalization failed for $RUNTIME $EVENT" >&2
  exit 2
fi

OUTPUT=$(printf '%s' "$NORMALIZED" | "$SCRIPT_DIR/../hooks/$POLICY" 2>&1)
STATUS=$?

if [ -n "${HARNESS_TRACE_FILE:-}" ]; then
  printf '%s' "$NORMALIZED" | "$SCRIPT_DIR/../hooks/trace-event.sh" "$POLICY" "$STATUS"
  TRACE_STATUS=$?
  if [ "$TRACE_STATUS" -ne 0 ] && [ "$POLICY" != "post-edit-format.sh" ]; then
    echo "BLOCKED by harness adapter: trace configuration failed" >&2
    exit 2
  fi
fi

[ -z "$OUTPUT" ] || printf '%s\n' "$OUTPUT" >&2
if [ "$STATUS" -eq 3 ]; then
  [ "$POLICY" = "post-edit-format.sh" ] && exit 0
  echo "BLOCKED by harness adapter: policy could not be evaluated" >&2
  exit 2
fi
exit "$STATUS"
