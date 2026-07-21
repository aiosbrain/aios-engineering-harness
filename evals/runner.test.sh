#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
STAMP="runner-test-$$"

run_case() {
  local mode="$1" want="$2"
  local dir="$ROOT/evals/results/$STAMP-$mode"
  bash "$ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 \
    --mock-mode "$mode" --results-dir "$dir" >/dev/null
  local got
  got=$(jq -r '.runs[0].status' "$dir/summary.json")
  if [ "$got" = "$want" ]; then
    PASS=$((PASS+1)); echo "PASS: mock $mode -> $want"
  else
    FAIL=$((FAIL+1)); echo "FAIL: mock $mode -> $got (want $want)"
  fi
}

run_case success pass
run_case failure error
run_case timeout timeout
run_case malformed error
run_case unavailable unavailable

REVIEW_DIR="$ROOT/evals/results/$STAMP-review"
bash "$ROOT/evals/run.sh" --runtime mock --scenario review-honesty-clean-diff --runs 1 \
  --results-dir "$REVIEW_DIR" >/dev/null
if [ "$(jq -r '.runs[0].status' "$REVIEW_DIR/summary.json")" = needs_review ]; then
  PASS=$((PASS+1)); echo "PASS: missing semantic judge -> needs_review"
else
  FAIL=$((FAIL+1)); echo "FAIL: missing semantic judge was counted as complete"
fi

ALL_DIR="$ROOT/evals/results/$STAMP-all"
bash "$ROOT/evals/run.sh" --runtime mock --scenario all --runs 1 --judge mock \
  --results-dir "$ALL_DIR" >/dev/null
EXPECTED_TOTAL=0
for MANIFEST in "$ROOT"/evals/scenarios/*/manifest.json; do
  [ -f "$MANIFEST" ] || continue
  SCENARIO_DIR_CHECK=$(dirname "$MANIFEST")
  if [ -x "$SCENARIO_DIR_CHECK/setup.sh" ] && [ -x "$SCENARIO_DIR_CHECK/grade.sh" ] && [ -f "$SCENARIO_DIR_CHECK/prompt.md" ]; then
    EXPECTED_TOTAL=$((EXPECTED_TOTAL+1))
  fi
done
if jq -e --argjson n "$EXPECTED_TOTAL" '.total == $n and .by_status.pass == $n and .pass_rate == 1' "$ALL_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: aggregate summary"
else
  FAIL=$((FAIL+1)); echo "FAIL: aggregate summary"
fi

INSTALL_ROOT=$(mktemp -d /tmp/harness-install-failure.XXXXXX)
mkdir -p "$INSTALL_ROOT/evals/lib" "$INSTALL_ROOT/evals/drivers" "$INSTALL_ROOT/evals/scenarios"
cp "$ROOT/evals/run.sh" "$INSTALL_ROOT/evals/run.sh"
cp "$ROOT/evals/lib/install-harness.sh" "$INSTALL_ROOT/evals/lib/install-harness.sh"
cp -R "$ROOT/evals/scenarios/tdd-under-deadline" "$INSTALL_ROOT/evals/scenarios/tdd-under-deadline"
DRIVER_MARKER="$INSTALL_ROOT/driver-ran"
printf '#!/bin/sh\ntouch "%s"\nexit 99\n' "$DRIVER_MARKER" > "$INSTALL_ROOT/evals/drivers/mock.sh"
chmod +x "$INSTALL_ROOT/evals/drivers/mock.sh"
INSTALL_RESULTS="$INSTALL_ROOT/results"
bash "$INSTALL_ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 \
  --results-dir "$INSTALL_RESULTS" >/dev/null 2>&1
if jq -e '.status == "error" and .reason == "harness installation failed"' \
    "$INSTALL_RESULTS/tdd-under-deadline-mock-1/run.json" >/dev/null &&
   jq -e '.total == 1 and .by_status.error == 1' "$INSTALL_RESULTS/summary.json" >/dev/null &&
   [ ! -e "$DRIVER_MARKER" ]; then
  PASS=$((PASS+1)); echo "PASS: install failure is recorded before driver execution"
else
  FAIL=$((FAIL+1)); echo "FAIL: install failure handling"
fi
rm -rf "$INSTALL_ROOT"

echo "runner.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
