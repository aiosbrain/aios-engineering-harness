#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d /tmp/harness-runtime-accounting.XXXXXX)
PASS=0
FAIL=0
trap 'rm -rf "$TMP"' EXIT

report() {
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS+1)); echo "PASS: $1"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $1"
  fi
}

run_driver() {
  local driver="$1" case_dir="$2"
  mkdir -p "$case_dir/bin" "$case_dir/run" "$case_dir/workspace"
  printf 'prompt\n' > "$case_dir/prompt.md"
  PATH="$case_dir/bin:$PATH" HARNESS_ROOT="$ROOT" HARNESS_WORKSPACE="$case_dir/workspace" \
    HARNESS_PROMPT_FILE="$case_dir/prompt.md" HARNESS_TRACE_FILE="$case_dir/trace.jsonl" \
    HARNESS_RUN_DIR="$case_dir/run" HARNESS_DRIVER_RECORD="$case_dir/run/driver.json" \
    HARNESS_MODEL=default HARNESS_TIMEOUT=10 bash "$ROOT/evals/drivers/$driver.sh" >/dev/null 2>&1
}

CLAUDE_PRESENT="$TMP/claude-present"
mkdir -p "$CLAUDE_PRESENT/bin"
printf '%s\n' '#!/bin/sh' \
  'echo "{\"type\":\"result\",\"usage\":{\"total_tokens\":10,\"input_tokens\":7,\"cache_read_input_tokens\":2,\"output_tokens\":3},\"total_cost_usd\":0.5}"' > "$CLAUDE_PRESENT/bin/claude"
chmod +x "$CLAUDE_PRESENT/bin/claude"
run_driver claude "$CLAUDE_PRESENT"
jq -e '.usage.cost_state == "runtime_reported" and .usage.cost_provenance == "runtime_reported" and .usage.runtime_cost == {source_field:"result.total_cost_usd",semantics:"runtime_reported_not_billed_or_actual"} and .usage.tokens == 10 and .usage.token_state == "partial"' "$CLAUDE_PRESENT/run/driver.json" >/dev/null 2>&1
report "claude numeric cost is runtime_reported, not billed, and total is provider-supplied" $?

CLAUDE_ABSENT="$TMP/claude-absent"
mkdir -p "$CLAUDE_ABSENT/bin"
printf '%s\n' '#!/bin/sh' 'echo "{\"type\":\"result\",\"usage\":{}}"' > "$CLAUDE_ABSENT/bin/claude"
chmod +x "$CLAUDE_ABSENT/bin/claude"
run_driver claude "$CLAUDE_ABSENT"
jq -e '.usage.tokens == null and .usage.token_state == "unknown" and .usage.cost_usd == null and .usage.cost_state == "unknown" and .usage.runtime_cost == null' "$CLAUDE_ABSENT/run/driver.json" >/dev/null 2>&1
report "claude absent telemetry remains unknown/null" $?

OPENCODE_PRESENT="$TMP/opencode-present"
mkdir -p "$OPENCODE_PRESENT/bin"
printf '%s\n' '#!/bin/sh' \
  'if [ "$1" = debug ]; then echo "{\"model\":\"provider/model\"}"; else echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":9,\"input\":6,\"output\":3,\"reasoning\":1},\"cost\":0.25}}"; fi' > "$OPENCODE_PRESENT/bin/opencode"
chmod +x "$OPENCODE_PRESENT/bin/opencode"
run_driver opencode "$OPENCODE_PRESENT"
jq -e '.usage.tokens == 9 and .usage.cached_input_tokens == null and .usage.token_state == "partial" and .usage.cost_state == "runtime_reported" and .usage.runtime_cost.source_field == "step_finish.part.cost"' "$OPENCODE_PRESENT/run/driver.json" >/dev/null 2>&1
report "opencode present numeric telemetry has explicit runtime provenance and partial dimensions" $?

CLAUDE_INVALID="$TMP/claude-invalid"
mkdir -p "$CLAUDE_INVALID/bin"
printf '%s\n' '#!/bin/sh' \
  'echo "{\"type\":\"result\",\"usage\":{\"total_tokens\":-1,\"input_tokens\":7.5,\"cache_read_input_tokens\":2,\"output_tokens\":\"3\"},\"total_cost_usd\":1e999}"' > "$CLAUDE_INVALID/bin/claude"
chmod +x "$CLAUDE_INVALID/bin/claude"
run_driver claude "$CLAUDE_INVALID"
jq -e '.usage.total_tokens == null and .usage.input_tokens == null and .usage.cached_input_tokens == 2 and .usage.output_tokens == null and .usage.cost_usd == null and .usage.cost_state == "unknown"' "$CLAUDE_INVALID/run/driver.json" >/dev/null 2>&1
report "claude rejects negative fractional and non-finite telemetry independently" $?

OPENCODE_INVALID="$TMP/opencode-invalid"
mkdir -p "$OPENCODE_INVALID/bin"
printf '%s\n' '#!/bin/sh' \
  'if [ "$1" = debug ]; then echo "{\"model\":\"provider/model\"}"; else echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":4,\"input\":2,\"output\":2},\"cost\":0.25}}"; echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":-1,\"input\":1.5,\"output\":1},\"cost\":1e999}}"; fi' > "$OPENCODE_INVALID/bin/opencode"
chmod +x "$OPENCODE_INVALID/bin/opencode"
run_driver opencode "$OPENCODE_INVALID"
jq -e '.usage.total_tokens == null and .usage.input_tokens == null and .usage.output_tokens == 3 and .usage.cost_usd == null and .usage.cost_state == "unknown"' "$OPENCODE_INVALID/run/driver.json" >/dev/null 2>&1
report "opencode validates every step before summing while retaining valid siblings" $?

echo "runtime-accounting.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
