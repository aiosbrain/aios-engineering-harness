#!/bin/sh
# Portable stop policy — skill-anchored, bounded continuation (protocol 1.1).
#
# Channel contract (unchanged for adapters that rely on exit codes): exit 0 allows
# the stop, exit 2 requests a continuation with the reason on stderr, exit 3 means
# the gate could not be evaluated. NEW in 1.1: on exit 2 the gate ALSO prints one
# `{"protocol":"1.1","action":"continue","reason":…}` envelope on stdout so
# structured adapters (run-hook translation, the OpenCode plugin, cursor/stop-gate)
# can consume the same reason without scraping stderr.
#
# Bounds and refusals:
#   - stop_status `aborted`/`error` never continues (exit 0, no action);
#   - loop_count >= HARNESS_STOP_CAP (default 1) allows the stop with an honest
#     "still red — human review" note instead of looping;
#   - the reason anchors the two fixed skills by ABSOLUTE path (verify-change +
#     systematic-debugging), re-injects the bounded agent digest, and quotes the
#     failed command plus a byte-capped, control-character-stripped output tail;
#   - a missing anchor skill file fails closed (exit 3, no continuation loop).
set -u

TAIL_CAP=2000

SCRIPT_DIR=$(CDPATH= cd -P -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -P -- "$SCRIPT_DIR/.." && pwd)
INPUT=$(cat 2>/dev/null || true)
EVENT=$(printf '%s' "$INPUT" | "$SCRIPT_DIR/prepare-event.sh" stop)
STATUS=$?
[ "$STATUS" -eq 4 ] && exit 0
[ "$STATUS" -eq 0 ] || exit 3

command -v jq >/dev/null 2>&1 || exit 3
CWD=$(printf '%s' "$EVENT" | jq -r '.cwd') || exit 3
LOOP_ACTIVE=$(printf '%s' "$EVENT" | jq -r '.stop.verification_loop_active') || exit 3
STOP_STATUS=$(printf '%s' "$EVENT" | jq -r '.stop.stop_status // "ok"') || exit 3
LOOP_COUNT=$(printf '%s' "$EVENT" | jq -r '.stop.loop_count // empty') || exit 3
case "$LOOP_COUNT" in
  ''|*[!0-9]*) [ "$LOOP_ACTIVE" = "true" ] && LOOP_COUNT=1 || LOOP_COUNT=0 ;;
esac
STOP_CAP=${HARNESS_STOP_CAP:-1}
case "$STOP_CAP" in ''|*[!0-9]*) STOP_CAP=1 ;; esac

# Aborted or errored stops are never continued — continuing a session the user
# killed (or that died) is exactly the runaway this gate exists to prevent.
case "$STOP_STATUS" in
  aborted|error) exit 0 ;;
esac

REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")

CHECK_CMD=${HARNESS_CHECK:-}
if [ -z "$CHECK_CMD" ] && [ -f "$REPO_ROOT/.harness/check" ]; then
  CHECK_CMD=$(head -5 "$REPO_ROOT/.harness/check" | grep -v '^#' | head -1)
fi
[ -n "$CHECK_CMD" ] || exit 0

if [ "$LOOP_COUNT" -ge "$STOP_CAP" ]; then
  echo "stop-verify-gate: check still failing after $LOOP_COUNT continuation(s) (cap $STOP_CAP); allowing stop for human review. Do not report this work as done." >&2
  exit 0
fi

OUTPUT=$(cd "$REPO_ROOT" && eval "$CHECK_CMD" 2>&1)
STATUS=$?
[ "$STATUS" -eq 0 ] && exit 0

# Red check: build the skill-anchored continuation. Anchors are fixed by design —
# the gate never infers a "last relevant skill".
VERIFY_SKILL="$ROOT/skills/verify-change/SKILL.md"
DEBUG_SKILL="$ROOT/skills/systematic-debugging/SKILL.md"
if [ ! -f "$VERIFY_SKILL" ] || [ ! -f "$DEBUG_SKILL" ]; then
  echo "stop-verify-gate: anchor skill missing (verify-change/systematic-debugging) — cannot build a continuation" >&2
  exit 3
fi

# Bounded digest: same source preference as inject-context.sh (repo-root copy when
# the pack is vendored at .harness). Missing digest degrades to no digest — the
# continuation itself must not die on a docs problem.
CONSTITUTION="$ROOT/CONSTITUTION.md"
if [ "$(basename -- "$ROOT")" = ".harness" ] && [ -f "$(dirname -- "$ROOT")/CONSTITUTION.md" ]; then
  CONSTITUTION="$(dirname -- "$ROOT")/CONSTITUTION.md"
fi
DIGEST=""
if [ -f "$CONSTITUTION" ]; then
  DIGEST=$(sed -n '/<!-- agent-digest:start -->/,/<!-- agent-digest:end -->/p' "$CONSTITUTION" | sed '1d;$d')
fi

# Byte-capped tail with control characters stripped (keep \n\t) so the reason is
# always JSON-safe and bounded no matter what the check printed.
TAIL=$(printf '%s\n' "$OUTPUT" | tail -c "$TAIL_CAP" | tr -d '\000-\010\013\014\016-\037\177')

REASON="The repository verification gate is red; the task is not done.
Check command: $CHECK_CMD (exit $STATUS)
Re-read these skills in full before continuing:
- $VERIFY_SKILL
- $DEBUG_SKILL
Failing output (last ${TAIL_CAP} bytes):
$TAIL

$DIGEST

Fix the failure or report the blocker honestly."

ACTION=$(jq -cn --arg reason "$REASON" '{protocol: "1.1", action: "continue", reason: $reason}' \
  | "$SCRIPT_DIR/validate-action.sh") || {
  echo "stop-verify-gate: could not build a valid continue action" >&2
  exit 3
}

printf '%s\n' "$ACTION"
printf '%s\n' "$REASON" >&2
exit 2
