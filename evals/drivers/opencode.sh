#!/bin/sh
set -u

START=$(date +%s)
STDOUT="$HARNESS_RUN_DIR/transcript.jsonl"
STDERR="$HARNESS_RUN_DIR/stderr.log"
MODEL=${HARNESS_MODEL:-default}

if ! command -v opencode >/dev/null 2>&1; then
  STATUS=127
elif [ "$MODEL" = "default" ] && ! opencode debug agent build 2>/dev/null | jq -e '.model != null' >/dev/null; then
  UNAVAILABLE_REASON='OpenCode has no default model configured; pass --model <provider/model>.'
  printf '%s\n' "$UNAVAILABLE_REASON" > "$STDERR"
  : > "$STDOUT"
  STATUS=127
else
  set -- opencode run --format json --auto --dir "$HARNESS_WORKSPACE"
  [ "$MODEL" = "default" ] || set -- "$@" --model "$MODEL"
  set -- "$@" "$(cat "$HARNESS_PROMPT_FILE")"
  HARNESS_TRACE_FILE="$HARNESS_TRACE_FILE" \
    python3 "$HARNESS_ROOT/evals/lib/exec_timeout.py" "$HARNESS_TIMEOUT" "$STDOUT" "$STDERR" -- "$@"
  STATUS=$?
fi

END=$(date +%s)
USAGE=$(jq -s '
  [.[] | select(.type == "step_finish") | .part] as $steps |
  def token: if type == "number" and isfinite and . >= 0 and floor == . and . <= 9007199254740991 then . else null end;
  def cost: if type == "number" and isfinite and . >= 0 and . <= 9007199254740991 then . else null end;
  def sum_tokens(path):
    if ($steps | length) == 0 then null
    else [$steps[] | (path | token)] as $values | if any($values[]; . == null) then null else ($values | add | token) end end;
  def sum_cost:
    if ($steps | length) == 0 then null
    else [$steps[] | (.cost | cost)] as $values | if any($values[]; . == null) then null else ($values | add | cost) end end;
  {tokens:sum_tokens(.tokens.total),total_tokens:sum_tokens(.tokens.total),input_tokens:sum_tokens(.tokens.input),
   cached_input_tokens:null,output_tokens:sum_tokens(.tokens.output),
   reasoning_output_tokens:sum_tokens(.tokens.reasoning),cost_usd:sum_cost} as $usage |
  $usage + {token_state:(if ([$usage.tokens,$usage.input_tokens,$usage.cached_input_tokens,$usage.output_tokens,$usage.reasoning_output_tokens] | all(.[]; type == "number")) then "complete" elif ([$usage.tokens,$usage.input_tokens,$usage.cached_input_tokens,$usage.output_tokens,$usage.reasoning_output_tokens] | any(.[]; type == "number")) then "partial" else "unknown" end),
             cost_state:(if $usage.cost_usd != null then "runtime_reported" else "unknown" end),
             cost_provenance:(if $usage.cost_usd != null then "runtime_reported" else "unknown" end),
             runtime_cost:(if $usage.cost_usd != null then {source_field:"step_finish.part.cost",semantics:"runtime_reported_not_billed_or_actual"} else null end)}
' "$STDOUT" 2>/dev/null || printf '%s' '{"tokens":null,"total_tokens":null,"input_tokens":null,"cached_input_tokens":null,"output_tokens":null,"reasoning_output_tokens":null,"cost_usd":null,"token_state":"unknown","cost_state":"unknown","cost_provenance":"unknown","runtime_cost":null}')
jq -n --arg runtime opencode --arg model "$MODEL" --arg transcript "$STDOUT" \
  --arg stderr "$STDERR" --arg reason "${UNAVAILABLE_REASON:-}" --argjson exit_status "$STATUS" \
  --argjson duration_ms "$(( (END-START)*1000 ))" --argjson usage "$USAGE" \
  '{runtime:$runtime,model:$model,exit_status:$exit_status,duration_ms:$duration_ms,transcript:$transcript,stderr:$stderr,usage:$usage}
   + (if $reason == "" then {} else {reason:$reason} end)' \
  > "$HARNESS_DRIVER_RECORD"
exit "$STATUS"
