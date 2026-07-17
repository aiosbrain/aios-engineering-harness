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
if jq -e '.total == 3 and .by_status.pass == 3 and .pass_rate == 1' "$ALL_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: aggregate summary"
else
  FAIL=$((FAIL+1)); echo "FAIL: aggregate summary"
fi

echo "runner.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
