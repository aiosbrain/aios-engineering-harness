#!/bin/sh
set -u

START=$(date +%s)
STDOUT="$HARNESS_RUN_DIR/transcript.jsonl"
STDERR="$HARNESS_RUN_DIR/stderr.log"
FINAL="$HARNESS_RUN_DIR/final.md"
MODEL=${HARNESS_MODEL:-default}
REASONING=${HARNESS_REASONING:-default}

toml_quote() {
  jq -Rn --arg value "$1" '$value'
}

hook_command() {
  printf '"%s/.harness/adapters/run-hook.sh" codex %s %s' "$HARNESS_WORKSPACE" "$1" "$2"
}

hook_entry() {
  EVENT=$1 POLICY=$2 TIMEOUT=$3
  COMMAND=$(toml_quote "$(hook_command "$EVENT" "$POLICY")")
  printf '{type="command",command=%s,timeout=%s}' "$COMMAND" "$TIMEOUT"
}

PROJECT_HOOKS="$HARNESS_WORKSPACE/.codex/hooks.json"
STASHED_HOOKS="$HARNESS_RUN_DIR/project-hooks.json"
restore_project_hooks() {
  if [ -f "$STASHED_HOOKS" ] && [ ! -e "$PROJECT_HOOKS" ]; then
    mv "$STASHED_HOOKS" "$PROJECT_HOOKS"
  fi
}
trap restore_project_hooks EXIT HUP INT TERM

if ! command -v codex >/dev/null 2>&1; then
  STATUS=127
  CLI_VERSION=unknown
else
  CLI_VERSION=$(codex --version 2>/dev/null | head -1 || true)
  [ -n "$CLI_VERSION" ] || CLI_VERSION=unknown
  SESSION_START=$(hook_entry session_start inject-context.sh 30)
  SUBAGENT_START=$(hook_entry subagent_start inject-context.sh 30)
  PROMPT_SUBMIT=$(hook_entry user_prompt_submit route-skills.sh 15)
  PRE_EDIT_SECRETS=$(hook_entry pre_edit guard-secrets.sh 30)
  PRE_EDIT_PATHS=$(hook_entry pre_edit guard-protected-paths.sh 30)
  PRE_EDIT_TREE=$(hook_entry pre_edit guard-worktree.sh 30)
  PRE_COMMAND_DESTRUCTIVE=$(hook_entry pre_command guard-destructive.sh 30)
  PRE_COMMAND_TREE=$(hook_entry pre_command guard-worktree.sh 30)
  PRE_COMMAND_OUTBOUND=$(hook_entry pre_command outbound-comms-guard.sh 30)
  POST_EDIT=$(hook_entry post_edit post-edit-format.sh 120)
  STOP=$(hook_entry stop stop-verify-gate.sh 600)
  # Codex 0.146.0 loads project hooks in headless mode. The eval driver supplies the
  # reviewed hooks explicitly, so temporarily hide the equivalent project file to
  # prevent every policy (including Stop) from firing twice. The EXIT trap restores it.
  if [ -f "$PROJECT_HOOKS" ] && [ ! -L "$PROJECT_HOOKS" ]; then
    mv "$PROJECT_HOOKS" "$STASHED_HOOKS"
  fi
  set -- codex exec --json --ephemeral --sandbox workspace-write --ignore-rules --enable hooks \
    --dangerously-bypass-hook-trust -c 'approval_policy="never"' \
    -c "hooks.SessionStart=[{hooks=[$SESSION_START]}]" \
    -c "hooks.SubagentStart=[{hooks=[$SUBAGENT_START]}]" \
    -c "hooks.UserPromptSubmit=[{hooks=[$PROMPT_SUBMIT]}]" \
    -c "hooks.PreToolUse=[{matcher=\"Edit|Write\",hooks=[$PRE_EDIT_SECRETS,$PRE_EDIT_PATHS,$PRE_EDIT_TREE]},{matcher=\"Bash\",hooks=[$PRE_COMMAND_DESTRUCTIVE,$PRE_COMMAND_TREE,$PRE_COMMAND_OUTBOUND]}]" \
    -c "hooks.PostToolUse=[{matcher=\"Edit|Write\",hooks=[$POST_EDIT]}]" \
    -c "hooks.Stop=[{hooks=[$STOP]}]" \
    --output-last-message "$FINAL" -C "$HARNESS_WORKSPACE"
  [ "$MODEL" = "default" ] || set -- "$@" --model "$MODEL"
  [ "$REASONING" = "default" ] || set -- "$@" -c "model_reasoning_effort=\"$REASONING\""
  set -- "$@" "$(cat "$HARNESS_PROMPT_FILE")"
  HARNESS_TRACE_FILE="$HARNESS_TRACE_FILE" \
    python3 "$HARNESS_ROOT/evals/lib/exec_timeout.py" "$HARNESS_TIMEOUT" "$STDOUT" "$STDERR" -- "$@"
  STATUS=$?
  restore_project_hooks
  # Only reclassify as "unavailable" when the process already failed AND produced no
  # genuine turn/item completion event at all — i.e. it never got past startup. A bare
  # substring check for `"type"` matches almost any JSONL line codex emits (every event
  # has a "type" key), so it rarely actually triggers; check for the specific terminal
  # marker normalize_transcript.py's codex() keys off instead. This keeps a transient
  # mid-run auth/rate-limit log line that the run recovers from (STATUS=0, or a real
  # completion event already in stdout) from being misreported, and confines the
  # keyword scan to stderr so legitimate agent transcript content (e.g. a security-
  # review scenario discussing "unauthorized access") in stdout is never matched.
  UNAVAILABLE_REASON=""
  if [ "$STATUS" -ne 0 ] && [ -z "$(jq -c 'select(.type == "item.completed")' "$STDOUT" 2>/dev/null | head -1)" ]; then
    UNAVAILABLE_REASON=$(grep -Eio 'not authenticated|not logged in|please log in|invalid api key|unauthorized|authentication required|rate limit exceeded|insufficient quota|quota exceeded' \
      "$STDERR" 2>/dev/null | head -1 || true)
  fi
  [ -z "$UNAVAILABLE_REASON" ] || STATUS=127
fi

END=$(date +%s)
USAGE=$(jq -s '
  ([.[] | select(.type == "turn.completed") | .usage] | last // {}) as $u |
  {tokens:(if (($u.input_tokens | type) == "number" and ($u.output_tokens | type) == "number")
           then ($u.input_tokens + $u.output_tokens) else null end),
   input_tokens:($u.input_tokens // null),cached_input_tokens:($u.cached_input_tokens // null),
   output_tokens:($u.output_tokens // null),reasoning_output_tokens:($u.reasoning_output_tokens // null),cost_usd:null}
' "$STDOUT" 2>/dev/null || printf '%s' '{"tokens":null,"cost_usd":null}')
jq -n --arg runtime codex --arg model "$MODEL" --arg transcript "$STDOUT" \
  --arg harness_sha "$(git -C "$HARNESS_ROOT" rev-parse HEAD 2>/dev/null || printf '%s' unknown)" \
  --arg reasoning "$REASONING" --arg cli_version "${CLI_VERSION:-unknown}" \
  --arg final "$FINAL" --arg stderr "$STDERR" --arg reason "${UNAVAILABLE_REASON:-}" --argjson exit_status "$STATUS" \
  --argjson duration_ms "$(( (END-START)*1000 ))" --argjson usage "$USAGE" \
  '{runtime:$runtime,model:$model,reasoning_level:$reasoning,cli_version:$cli_version,harness_sha:$harness_sha,exit_status:$exit_status,duration_ms:$duration_ms,transcript:$transcript,final:$final,stderr:$stderr,usage:$usage}
   + (if $reason == "" then {} else {reason:$reason} end)' \
  > "$HARNESS_DRIVER_RECORD"
exit "$STATUS"
