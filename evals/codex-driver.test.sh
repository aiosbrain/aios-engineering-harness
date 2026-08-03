#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TMP=$(mktemp -d /tmp/harness-codex-driver.XXXXXX)
trap 'rm -rf "$TMP"' EXIT

report() {
  local name="$1" status="$2"
  if [ "$status" -eq 0 ]; then
    PASS=$((PASS+1)); echo "PASS: $name"
  else
    FAIL=$((FAIL+1)); echo "FAIL: $name"
  fi
}

mkdir -p "$TMP/bin"

run_fake_codex() {
  local case_dir="$1"
  mkdir -p "$case_dir/run" "$case_dir/workspace"
  printf 'hello\n' > "$case_dir/prompt.md"
  PATH="$TMP/bin:$PATH" \
    HARNESS_ROOT="$ROOT" HARNESS_WORKSPACE="$case_dir/workspace" \
    HARNESS_PROMPT_FILE="$case_dir/prompt.md" HARNESS_TRACE_FILE="$case_dir/trace.jsonl" \
    HARNESS_RUN_DIR="$case_dir/run" HARNESS_DRIVER_RECORD="$case_dir/run/driver.json" \
    HARNESS_MODEL=default HARNESS_REASONING=high HARNESS_TIMEOUT=10 \
    bash "$ROOT/evals/drivers/codex.sh"
}

# Case A (true positive, must be preserved): no genuine turn/item completion event at
# all, process exits nonzero, and stderr carries an auth-failure phrase -> unavailable.
CASE_A="$TMP/case-a"
mkdir -p "$CASE_A"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
echo '{"type":"turn.started"}'
echo "Error: authentication required" >&2
exit 1
EOF
chmod +x "$TMP/bin/codex"
run_fake_codex "$CASE_A" >/dev/null 2>&1
jq -e '.exit_status == 127 and (.reason // "" | length) > 0' "$CASE_A/run/driver.json" >/dev/null 2>&1
report "codex.sh: no item.completed + nonzero exit + stderr auth phrase -> unavailable" $?

# Case B (false-negative regression guard): a genuine item.completed event IS present
# (real work happened) even though the process later crashes and stderr happens to
# contain a keyword-like phrase (e.g. legitimate transcript content) -> must classify
# as a plain error, not unavailable. This is the exact misclassification the
# tightened check must avoid.
CASE_B="$TMP/case-b"
mkdir -p "$CASE_B"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
echo '{"type":"item.completed","item":{"type":"command_execution"}}'
echo "reviewed: unauthorized access is not possible here" >&2
exit 1
EOF
chmod +x "$TMP/bin/codex"
run_fake_codex "$CASE_B" >/dev/null 2>&1
jq -e '.exit_status == 1' "$CASE_B/run/driver.json" >/dev/null 2>&1
report "codex.sh: item.completed present -> stays error, not misclassified unavailable" $?

# Case C: headless runs must inject every required project hook explicitly because
# Codex exec does not load .codex/hooks.json reliably. The fake records argv without
# printing it into a tracked fixture.
CASE_C="$TMP/case-c"
mkdir -p "$CASE_C"
mkdir -p "$CASE_C/workspace/.codex"
printf '%s\n' '{"hooks":{"SessionStart":[]}}' > "$CASE_C/workspace/.codex/hooks.json"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HARNESS_RUN_DIR/argv.txt"
echo '{"type":"turn.started"}'
echo '{"type":"turn.completed","usage":{"input_tokens":1,"output_tokens":1}}'
exit 0
EOF
chmod +x "$TMP/bin/codex"
run_fake_codex "$CASE_C" >/dev/null 2>&1
if [ -f "$CASE_C/workspace/.codex/hooks.json" ] && [ ! -e "$CASE_C/run/project-hooks.json" ]; then
  report "codex.sh: project hooks restored after explicit headless injection" 0
else
  report "codex.sh: project hooks restored after explicit headless injection" 1
fi
for REQUIRED in hooks.SessionStart hooks.SubagentStart hooks.UserPromptSubmit hooks.PreToolUse hooks.PostToolUse hooks.Stop 'model_reasoning_effort="high"'; do
  grep -F "$REQUIRED" "$CASE_C/run/argv.txt" >/dev/null 2>&1 || { report "codex.sh: explicit headless hook/reasoning injection ($REQUIRED)" 1; continue; }
  report "codex.sh: explicit headless hook/reasoning injection ($REQUIRED)" 0
done
jq -e '.usage.tokens == null and .usage.input_tokens == 1 and .usage.output_tokens == 1 and .usage.token_state == "partial" and .usage.cost_usd == null and .usage.cost_state == "unknown" and .usage.cost_provenance == "unknown"' "$CASE_C/run/driver.json" >/dev/null 2>&1
report "codex.sh: absent provider total stays null with partial token telemetry" $?

# Case D: a present-but-partial usage object must not be coerced to zero.
CASE_D="$TMP/case-d"
mkdir -p "$CASE_D"
cat > "$TMP/bin/codex" <<'EOF'
#!/bin/sh
echo '{"type":"turn.started"}'
echo '{"type":"turn.completed","usage":{"cached_input_tokens":9}}'
exit 0
EOF
chmod +x "$TMP/bin/codex"
run_fake_codex "$CASE_D" >/dev/null 2>&1
jq -e '.usage.tokens == null and .usage.input_tokens == null and .usage.cached_input_tokens == 9 and .usage.output_tokens == null and .usage.token_state == "partial" and .usage.cost_usd == null' \
  "$CASE_D/run/driver.json" >/dev/null 2>&1
report "codex.sh: partial usage remains unknown rather than zero" $?

echo "codex-driver.test.sh: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || exit 1
