#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
STAMP="runner-test-$$"

python3 "$ROOT/evals/accounting.test.py" >/dev/null || { echo "FAIL: accounting contract suite"; exit 1; }
bash "$ROOT/evals/runtime-accounting.test.sh" >/dev/null || { echo "FAIL: runtime accounting suite"; exit 1; }

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
run_case garbage-mode error

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
  # Mirrors run.sh's own --scenario all completeness gate exactly (including the
  # rubric.md-required-when-semantic_required clause) so this count can never
  # diverge from what run.sh actually decides to include.
  SCENARIO_SEMANTIC=$(jq -r '.semantic_required // false' "$MANIFEST" 2>/dev/null || echo false)
  if [ -x "$SCENARIO_DIR_CHECK/setup.sh" ] && [ -x "$SCENARIO_DIR_CHECK/grade.sh" ] && [ -f "$SCENARIO_DIR_CHECK/prompt.md" ] \
    && { [ "$SCENARIO_SEMANTIC" != true ] || [ -f "$SCENARIO_DIR_CHECK/rubric.md" ]; }; then
    EXPECTED_TOTAL=$((EXPECTED_TOTAL+1))
  fi
done
if jq -e --argjson n "$EXPECTED_TOTAL" '.total == $n and .by_status.pass == $n and .pass_rate == 1' "$ALL_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: aggregate summary"
else
  FAIL=$((FAIL+1)); echo "FAIL: aggregate summary"
fi
if jq -e '.accounting.attempt_count == .total and (.accounting.rollups.by_attempt | length) == .total' "$ALL_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: aggregate summary contains exact-once accounting rollups"
else
  FAIL=$((FAIL+1)); echo "FAIL: aggregate accounting rollups"
fi

EXPLICIT_ALL_DIR="$ROOT/evals/results/$STAMP-all-explicit"
bash "$ROOT/evals/run.sh" --runtime mock --scenario all --runs 1 --attempt-id logical-all --results-dir "$EXPLICIT_ALL_DIR" >/dev/null
if jq -e --argjson n "$EXPECTED_TOTAL" '.total == $n and (.runs | length) == $n and ([.runs[] | .attempt_id == "logical-all"] | all) and ([.runs[] | [.invocation_id,.run_id] | @json] | unique | length) == $n and (.accounting.rollups.by_attempt | length) == 1 and .accounting.rollups.by_attempt["unknown/unknown/scenario/logical-all"].attempt_count == $n' "$EXPLICIT_ALL_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: explicit attempt ID groups all scenario runs without replay collisions"
else
  FAIL=$((FAIL+1)); echo "FAIL: explicit attempt ID replay identity"
fi

OUTCOME_DIR="$ROOT/evals/results/$STAMP-outcome"
bash "$ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 --phase review --role reviewer \
  --program-id eval-program --issue-id AIO-709 --outcome-id AIO-709:mock-verified --results-dir "$OUTCOME_DIR" >/dev/null
if jq -e '.accounting.outcome_count == 0 and .runs[0].verified_outcome == null and .runs[0].outcome_claim_status == "rejected"' "$OUTCOME_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: incomplete reviewer evidence cannot claim an independently verified outcome"
else
  FAIL=$((FAIL+1)); echo "FAIL: verified outcome accounting"
fi

REJECTED_OUTCOME_DIR="$ROOT/evals/results/$STAMP-outcome-rejected"
bash "$ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 --mock-mode failure --phase review --role reviewer \
  --program-id eval-program --issue-id AIO-709 --outcome-id AIO-709:rejected --results-dir "$REJECTED_OUTCOME_DIR" >/dev/null
if jq -e '.accounting.outcome_count == 0 and .runs[0].outcome_claim_status == "rejected" and .runs[0].verified_outcome == null' "$REJECTED_OUTCOME_DIR/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: non-pass reviewer outcome claim is rejected"
else
  FAIL=$((FAIL+1)); echo "FAIL: non-pass outcome claim"
fi

INSTALL_ROOT=$(mktemp -d /tmp/harness-install-failure.XXXXXX)
mkdir -p "$INSTALL_ROOT/evals/lib" "$INSTALL_ROOT/evals/drivers" "$INSTALL_ROOT/evals/scenarios"
cp "$ROOT/evals/run.sh" "$INSTALL_ROOT/evals/run.sh"
cp "$ROOT/evals/lib/install-harness.sh" "$INSTALL_ROOT/evals/lib/install-harness.sh"
cp "$ROOT/evals/lib/accounting.py" "$INSTALL_ROOT/evals/lib/accounting.py"
cp "$ROOT/evals/lib/build_observations.py" "$INSTALL_ROOT/evals/lib/build_observations.py"
cp "$ROOT/evals/lib/normalize_transcript.py" "$INSTALL_ROOT/evals/lib/normalize_transcript.py"
cp -R "$ROOT/evals/scenarios/tdd-under-deadline" "$INSTALL_ROOT/evals/scenarios/tdd-under-deadline"
DRIVER_MARKER="$INSTALL_ROOT/driver-ran"
printf '#!/bin/sh\ntouch "%s"\nexit 99\n' "$DRIVER_MARKER" > "$INSTALL_ROOT/evals/drivers/mock.sh"
chmod +x "$INSTALL_ROOT/evals/drivers/mock.sh"
INSTALL_RESULTS="$INSTALL_ROOT/results"
bash "$INSTALL_ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 \
  --results-dir "$INSTALL_RESULTS" >/dev/null 2>&1
INSTALL_STATUS=$?
if [ "$INSTALL_STATUS" -eq 0 ] &&
   jq -e '.status == "error" and .reason == "harness installation failed"' \
    "$INSTALL_RESULTS/tdd-under-deadline-mock-1/run.json" >/dev/null &&
   jq -e '.observation_completeness.verdict == "error" and .observation_completeness.issues[0].attribution == "harness"' \
    "$INSTALL_RESULTS/tdd-under-deadline-mock-1/run.json" >/dev/null &&
   jq -e '.event == "phase.gate" and .status == "error" and .attribution == "harness"' \
    "$INSTALL_RESULTS/tdd-under-deadline-mock-1/observations.v1.jsonl" >/dev/null &&
   jq -e '.total == 1 and .by_status.error == 1 and .accounting.attempt_count == 1' "$INSTALL_RESULTS/summary.json" >/dev/null &&
   [ -f "$INSTALL_RESULTS/accounting.json" ] &&
   [ ! -e "$DRIVER_MARKER" ]; then
  PASS=$((PASS+1)); echo "PASS: install failure is recorded before driver execution"
else
  FAIL=$((FAIL+1)); echo "FAIL: install failure handling"
fi
rm -rf "$INSTALL_ROOT"

CONSUMER_ROOT=$(mktemp -d /tmp/harness-consumer-compat.XXXXXX)
mkdir -p "$CONSUMER_ROOT/evals/lib" "$CONSUMER_ROOT/evals/drivers" "$CONSUMER_ROOT/evals/scenarios"
cp "$ROOT/evals/run.sh" "$CONSUMER_ROOT/evals/run.sh"
cp "$ROOT/evals/lib/normalize_transcript.py" "$CONSUMER_ROOT/evals/lib/normalize_transcript.py"
printf '#!/bin/sh\nmkdir -p "$2/.git/info"\nprintf ".eval/\\n" >> "$2/.git/info/exclude"\n' > "$CONSUMER_ROOT/evals/lib/install-harness.sh"
chmod +x "$CONSUMER_ROOT/evals/lib/install-harness.sh"
cp "$ROOT/evals/drivers/mock.sh" "$CONSUMER_ROOT/evals/drivers/mock.sh"
cp -R "$ROOT/evals/scenarios/tdd-under-deadline" "$CONSUMER_ROOT/evals/scenarios/tdd-under-deadline"
CONSUMER_RESULTS="$CONSUMER_ROOT/results"
bash "$CONSUMER_ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 \
  --results-dir "$CONSUMER_RESULTS" >/dev/null 2>&1
CONSUMER_STATUS=$?
if [ "$CONSUMER_STATUS" -eq 0 ] &&
   jq -e '(.runs[0].status | type == "string") and (.accounting.state == "legacy_unknown") and (.accounting.reason | contains("sync lib/accounting.py"))' "$CONSUMER_RESULTS/summary.json" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: vendored consumer without new modules degrades to explicit legacy/unknown accounting"
else
  FAIL=$((FAIL+1)); echo "FAIL: vendored consumer compatibility fallback"
fi
rm -rf "$CONSUMER_ROOT"

BUILDER_ROOT=$(mktemp -d /tmp/harness-observation-builder-failure.XXXXXX)
mkdir -p "$BUILDER_ROOT/evals/lib" "$BUILDER_ROOT/evals/drivers" "$BUILDER_ROOT/evals/scenarios"
cp "$ROOT/evals/run.sh" "$BUILDER_ROOT/evals/run.sh"
cp "$ROOT/evals/lib/accounting.py" "$BUILDER_ROOT/evals/lib/accounting.py"
cp "$ROOT/evals/lib/normalize_transcript.py" "$BUILDER_ROOT/evals/lib/normalize_transcript.py"
printf '#!/usr/bin/env python3\nraise SystemExit(1)\n' > "$BUILDER_ROOT/evals/lib/build_observations.py"
printf '#!/bin/sh\nexit 0\n' > "$BUILDER_ROOT/evals/lib/install-harness.sh"
chmod +x "$BUILDER_ROOT/evals/lib/install-harness.sh"
cp "$ROOT/evals/drivers/mock.sh" "$BUILDER_ROOT/evals/drivers/mock.sh"
cp -R "$ROOT/evals/scenarios/tdd-under-deadline" "$BUILDER_ROOT/evals/scenarios/tdd-under-deadline"
BUILDER_RESULTS="$BUILDER_ROOT/results"
bash "$BUILDER_ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 \
  --results-dir "$BUILDER_RESULTS" >/dev/null 2>&1
BUILDER_STATUS=$?
if [ "$BUILDER_STATUS" -eq 0 ] &&
   jq -e '(.status == "error") and (.program_id == "unknown") and (.attempt_id | length > 0) and (.current_sha | type == "string") and (.usage.total_tokens == null) and (.usage.input_tokens == null) and (.usage.cached_input_tokens == null) and (.usage.output_tokens == null) and (.usage.reasoning_output_tokens == null) and (.usage.token_state == "unknown") and (.usage.cost_state == "unknown")' "$BUILDER_RESULTS/tdd-under-deadline-mock-1/run.json" >/dev/null &&
   jq -e '.event == "phase.gate" and .status == "error" and .summary.reason == "observation builder failed"' "$BUILDER_RESULTS/tdd-under-deadline-mock-1/observations.v1.jsonl" >/dev/null; then
  PASS=$((PASS+1)); echo "PASS: observation-builder failure emits a full typed terminal accounting fallback"
else
  FAIL=$((FAIL+1)); echo "FAIL: observation-builder failure fallback"
fi
rm -rf "$BUILDER_ROOT"

EMPTY_ROOT=$(mktemp -d /tmp/harness-empty-scenarios.XXXXXX)
mkdir -p "$EMPTY_ROOT/evals/lib" "$EMPTY_ROOT/evals/drivers" "$EMPTY_ROOT/evals/scenarios"
cp "$ROOT/evals/run.sh" "$EMPTY_ROOT/evals/run.sh"
cp "$ROOT/evals/lib/install-harness.sh" "$EMPTY_ROOT/evals/lib/install-harness.sh"
cp "$ROOT/evals/drivers/mock.sh" "$EMPTY_ROOT/evals/drivers/mock.sh"
EMPTY_RESULTS="$EMPTY_ROOT/results"
# No portable `timeout`/`gtimeout` binary assumed available (macOS ships neither by
# default) — use a plain bash watchdog so a regression that reintroduces the hang
# fails this test loudly instead of hanging the whole suite.
bash "$EMPTY_ROOT/evals/run.sh" --runtime mock --scenario all --runs 1 \
  --results-dir "$EMPTY_RESULTS" >/dev/null 2>&1 &
EMPTY_PID=$!
( sleep 10; kill -9 "$EMPTY_PID" 2>/dev/null ) &
WATCHDOG_PID=$!
wait "$EMPTY_PID" 2>/dev/null
EMPTY_STATUS=$?
kill "$WATCHDOG_PID" 2>/dev/null
wait "$WATCHDOG_PID" 2>/dev/null
if [ "$EMPTY_STATUS" -eq 3 ]; then
  PASS=$((PASS+1)); echo "PASS: --scenario all with zero complete scenarios exits cleanly (not a crash/hang)"
else
  FAIL=$((FAIL+1)); echo "FAIL: --scenario all with zero complete scenarios exited $EMPTY_STATUS (want 3; 124 would mean the old hang came back)"
fi
rm -rf "$EMPTY_ROOT"

SCRATCH_BEFORE=$(find "$ROOT/evals/scratch" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
CLEANUP_DIR="$ROOT/evals/results/$STAMP-cleanup"
bash "$ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 \
  --results-dir "$CLEANUP_DIR" >/dev/null
SCRATCH_AFTER=$(find "$ROOT/evals/scratch" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
if [ "$SCRATCH_AFTER" = "$SCRATCH_BEFORE" ]; then
  PASS=$((PASS+1)); echo "PASS: scratch workspace is cleaned up after a normal run"
else
  FAIL=$((FAIL+1)); echo "FAIL: scratch workspace leaked after a normal run"
fi

KEEP_DIR="$ROOT/evals/results/$STAMP-keep"
bash "$ROOT/evals/run.sh" --runtime mock --scenario tdd-under-deadline --runs 1 --keep-workspaces \
  --results-dir "$KEEP_DIR" >/dev/null
SCRATCH_AFTER_KEEP=$(find "$ROOT/evals/scratch" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
NEW_KEPT_DIRS=$(comm -13 <(echo "$SCRATCH_BEFORE") <(echo "$SCRATCH_AFTER_KEEP"))
if [ -n "$NEW_KEPT_DIRS" ]; then
  PASS=$((PASS+1)); echo "PASS: --keep-workspaces preserves the scratch workspace"
else
  FAIL=$((FAIL+1)); echo "FAIL: --keep-workspaces did not preserve the scratch workspace"
fi
[ -z "$NEW_KEPT_DIRS" ] || echo "$NEW_KEPT_DIRS" | xargs -I{} rm -rf {}

FORBIDDEN_ROOT=$(mktemp -d /tmp/harness-forbidden.XXXXXX)
mkdir -p "$FORBIDDEN_ROOT/evals/lib" "$FORBIDDEN_ROOT/evals/drivers" "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario"
cp "$ROOT/evals/run.sh" "$FORBIDDEN_ROOT/evals/run.sh"
cp "$ROOT/evals/lib/accounting.py" "$FORBIDDEN_ROOT/evals/lib/accounting.py"
cp "$ROOT/evals/lib/build_observations.py" "$FORBIDDEN_ROOT/evals/lib/build_observations.py"
cp "$ROOT/evals/lib/normalize_transcript.py" "$FORBIDDEN_ROOT/evals/lib/normalize_transcript.py"
printf '#!/bin/sh\nexit 0\n' > "$FORBIDDEN_ROOT/evals/lib/install-harness.sh"
chmod +x "$FORBIDDEN_ROOT/evals/lib/install-harness.sh"
printf '{"id":"tamper-scenario","title":"tamper test","timeout_seconds":60,"semantic_required":false,"forbidden_paths":[".secret"]}\n' \
  > "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario/manifest.json"
printf 'noop\n' > "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario/prompt.md"
cat > "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario/setup.sh" <<'EOF'
#!/bin/sh
set -eu
git init -q
git config user.email a@b.c
git config user.name test
printf 'original\n' > .secret
git add -A
git commit -qm init
EOF
chmod +x "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario/setup.sh"
printf '#!/bin/sh\necho '"'"'{"checks":{},"deterministic_pass":true}'"'"'\n' \
  > "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario/grade.sh"
chmod +x "$FORBIDDEN_ROOT/evals/scenarios/tamper-scenario/grade.sh"
cat > "$FORBIDDEN_ROOT/evals/drivers/mock.sh" <<'EOF'
#!/bin/sh
set -u
cd "$HARNESS_WORKSPACE"
printf 'tampered\n' > .secret
exit 1
EOF
chmod +x "$FORBIDDEN_ROOT/evals/drivers/mock.sh"
FORBIDDEN_RESULTS="$FORBIDDEN_ROOT/results"
bash "$FORBIDDEN_ROOT/evals/run.sh" --runtime mock --scenario tamper-scenario --runs 1 \
  --results-dir "$FORBIDDEN_RESULTS" >/dev/null 2>&1
if jq -e '.runs[0].status == "fail" and .runs[0].forbidden_path_hit == true' "$FORBIDDEN_RESULTS/summary.json" >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS: forbidden-path tamper ranks above a driver error and survives into summary.json"
else
  FAIL=$((FAIL+1)); echo "FAIL: forbidden-path tamper not surfaced correctly in summary.json"
fi
rm -rf "$FORBIDDEN_ROOT"

echo "runner.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
