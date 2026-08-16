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

CLAUDE_OVERSIZED="$TMP/claude-oversized"
mkdir -p "$CLAUDE_OVERSIZED/bin"
printf '%s\n' '#!/bin/sh' \
  'echo "{\"type\":\"result\",\"usage\":{\"total_tokens\":9007199254740992,\"input_tokens\":1},\"total_cost_usd\":9007199254740992}"' > "$CLAUDE_OVERSIZED/bin/claude"
chmod +x "$CLAUDE_OVERSIZED/bin/claude"
run_driver claude "$CLAUDE_OVERSIZED"
jq -e '.usage.total_tokens == null and .usage.input_tokens == 1 and .usage.cost_usd == null and .usage.cost_state == "unknown"' "$CLAUDE_OVERSIZED/run/driver.json" >/dev/null 2>&1
report "claude rejects oversized JSON-unsafe token and runtime cost fields independently" $?

OPENCODE_INVALID="$TMP/opencode-invalid"
mkdir -p "$OPENCODE_INVALID/bin"
printf '%s\n' '#!/bin/sh' \
  'if [ "$1" = debug ]; then echo "{\"model\":\"provider/model\"}"; else echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":4,\"input\":2,\"output\":2},\"cost\":0.25}}"; echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":-1,\"input\":1.5,\"output\":1},\"cost\":1e999}}"; fi' > "$OPENCODE_INVALID/bin/opencode"
chmod +x "$OPENCODE_INVALID/bin/opencode"
run_driver opencode "$OPENCODE_INVALID"
jq -e '.usage.total_tokens == null and .usage.input_tokens == null and .usage.output_tokens == 3 and .usage.cost_usd == null and .usage.cost_state == "unknown"' "$OPENCODE_INVALID/run/driver.json" >/dev/null 2>&1
report "opencode validates every step before summing while retaining valid siblings" $?

OPENCODE_OVERSIZED="$TMP/opencode-oversized"
mkdir -p "$OPENCODE_OVERSIZED/bin"
printf '%s\n' '#!/bin/sh' \
  'if [ "$1" = debug ]; then echo "{\"model\":\"provider/model\"}"; else echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":9007199254740992,\"input\":1,\"output\":1},\"cost\":9007199254740992}}"; fi' > "$OPENCODE_OVERSIZED/bin/opencode"
chmod +x "$OPENCODE_OVERSIZED/bin/opencode"
run_driver opencode "$OPENCODE_OVERSIZED"
jq -e '.usage.total_tokens == null and .usage.input_tokens == 1 and .usage.output_tokens == 1 and .usage.cost_usd == null and .usage.cost_state == "unknown"' "$OPENCODE_OVERSIZED/run/driver.json" >/dev/null 2>&1
report "opencode rejects oversized operands while retaining valid siblings" $?

OPENCODE_OVERFLOW="$TMP/opencode-overflow"
mkdir -p "$OPENCODE_OVERFLOW/bin"
printf '%s\n' '#!/bin/sh' \
  'if [ "$1" = debug ]; then echo "{\"model\":\"provider/model\"}"; else echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":9007199254740991,\"input\":1,\"output\":1},\"cost\":9007199254740991}}"; echo "{\"type\":\"step_finish\",\"part\":{\"tokens\":{\"total\":1,\"input\":1,\"output\":1},\"cost\":1}}"; fi' > "$OPENCODE_OVERFLOW/bin/opencode"
chmod +x "$OPENCODE_OVERFLOW/bin/opencode"
run_driver opencode "$OPENCODE_OVERFLOW"
jq -e '.usage.total_tokens == null and .usage.input_tokens == 2 and .usage.output_tokens == 2 and .usage.cost_usd == null and .usage.cost_state == "unknown"' "$OPENCODE_OVERFLOW/run/driver.json" >/dev/null 2>&1
report "opencode rejects JSON-unsafe post-sum overflow without poisoning valid siblings" $?

# Real recorded Claude usage: input_tokens is the uncached remainder only, so cached input
# dwarfs it and cache creation is a billed dimension of its own.
FIXTURE="$ROOT/evals/fixtures/accounting/claude-cache-usage.json"
CLAUDE_CACHED="$TMP/claude-cached"
mkdir -p "$CLAUDE_CACHED/bin"
jq -c '{type:"result",usage:.result.usage,total_cost_usd:.result.total_cost_usd}' "$FIXTURE" > "$CLAUDE_CACHED/result.json"
printf '%s\n' '#!/bin/sh' "cat '$CLAUDE_CACHED/result.json'" > "$CLAUDE_CACHED/bin/claude"
chmod +x "$CLAUDE_CACHED/bin/claude"
run_driver claude "$CLAUDE_CACHED"
jq -e --slurpfile fixture "$FIXTURE" '
  ($fixture[0].result.usage) as $recorded | ($fixture[0].expected) as $expected |
  .usage.token_model == "disjoint_input_v1" and
  .usage.input_tokens == $recorded.input_tokens and
  .usage.cached_input_tokens == $recorded.cache_read_input_tokens and
  .usage.cache_read_input_tokens == $recorded.cache_read_input_tokens and
  .usage.cache_creation_input_tokens == $recorded.cache_creation_input_tokens and
  .usage.output_tokens == $recorded.output_tokens and
  .usage.total_tokens == $expected.total_tokens and .usage.tokens == $expected.total_tokens and
  .usage.total_tokens != $expected.subset_model_undercount and
  .usage.cost_state == "runtime_reported"' "$CLAUDE_CACHED/run/driver.json" >/dev/null 2>&1
report "claude records cache creation and totals the disjoint dimensions from a real cached run" $?

CLAUDE_PARTIAL="$TMP/claude-partial"
mkdir -p "$CLAUDE_PARTIAL/bin"
printf '%s\n' '#!/bin/sh' \
  'echo "{\"type\":\"result\",\"usage\":{\"input_tokens\":5,\"cache_read_input_tokens\":7,\"output_tokens\":3}}"' > "$CLAUDE_PARTIAL/bin/claude"
chmod +x "$CLAUDE_PARTIAL/bin/claude"
run_driver claude "$CLAUDE_PARTIAL"
jq -e '.usage.cache_creation_input_tokens == null and .usage.total_tokens == null and .usage.tokens == null and .usage.input_tokens == 5 and .usage.token_state == "partial"' "$CLAUDE_PARTIAL/run/driver.json" >/dev/null 2>&1
report "claude never invents a total while a disjoint dimension is missing" $?

echo "runtime-accounting.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
