#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNTIME=""
SCENARIO=""
RUNS=1
MODEL=default
JUDGE=none
JUDGE_MODEL=default
TIMEOUT_OVERRIDE=""
RESULTS_DIR=""
MOCK_MODE=success
KEEP_WORKSPACES=false
REASONING=default
PHASE=scenario
ROLE=agent
PROGRAM_ID=unknown
ISSUE_ID=unknown
ATTEMPT_ID=""
OUTCOME_ID=""
SUBJECT_ATTEMPT_ID=""
INVOCATION_ID=""

usage() {
  echo "usage: bash evals/run.sh --runtime <claude|codex|opencode|mock> --scenario <id|all> --runs <n> [--model id] [--reasoning level] [--phase name] [--role name] [--program-id id] [--issue-id id] [--attempt-id id] [--outcome-id id --subject-attempt-id id] [--judge <runtime|none>] [--keep-workspaces]" >&2
}

cleanup_scratch() {
  [ "$KEEP_WORKSPACES" = true ] || rm -rf "$SCRATCH_DIR"
}

# Filesystem-level fingerprint of a scenario's forbidden_paths, independent of git
# visibility: a consumer's install-harness.sh may add its own scaffolding dirs to
# .git/info/exclude (this repo's does, for .harness/, .claude/, etc.), which would
# make a git-diff/status-based tamper check structurally blind to edits under
# those same paths.
fingerprint_forbidden() {
  WORKSPACE_ARG=$1
  PATHS_JSON=$2
  printf '%s' "$PATHS_JSON" | jq -r '.[]' | while IFS= read -r REL; do
    TARGET="$WORKSPACE_ARG/$REL"
    if [ -e "$TARGET" ]; then
      find "$TARGET" -type f -print0 2>/dev/null | xargs -0 cksum 2>/dev/null | sort
    else
      printf '%s: absent\n' "$REL"
    fi
  done
}

write_early_failure() {
  ATTRIBUTION=$1
  REASON=$2
  EMPTY_HASH=sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  EARLY_SHA=$(git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null || printf '%s' unknown)
  jq -nc --arg id "$RUN_ID" --arg phase "$PHASE" --arg role "$ROLE" --arg program_id "$PROGRAM_ID" --arg issue_id "$ISSUE_ID" --arg invocation_id "$INVOCATION_ID" --arg attempt_id "$RUN_ATTEMPT_ID" \
    --arg runtime "$RUNTIME" --arg model "$MODEL" --arg reasoning "$REASONING" \
    --arg sha "$EARLY_SHA" --arg diff_hash "$EMPTY_HASH" --arg attribution "$ATTRIBUTION" \
    --arg reason "$REASON" \
    '{schema_version:"observations.v1",run_id:$id,phase:$phase,role:$role,runtime:$runtime,
      program_id:$program_id,issue_id:$issue_id,invocation_id:$invocation_id,attempt_id:$attempt_id,model:$model,runtime_version:"unknown",harness_sha:"unknown",reasoning_level:$reasoning,turn_id:($id+":phase"),item_id:null,sequence:1,
      frozen_sha:$sha,current_sha:$sha,diff_hash:$diff_hash,event:"phase.gate",status:"error",
      source_artifact:"runner",severity:"error",attribution:$attribution,summary:{reason:$reason}}' \
    > "$OBSERVATIONS"
  jq -n --arg id "$RUN_ID" --arg attribution "$ATTRIBUTION" --arg reason "$REASON" --arg program_id "$PROGRAM_ID" --arg issue_id "$ISSUE_ID" --arg phase "$PHASE" --arg role "$ROLE" --arg invocation_id "$INVOCATION_ID" --arg attempt_id "$RUN_ATTEMPT_ID" \
    '{schema_version:"observations.v1",program_id:$program_id,issue_id:$issue_id,phase:$phase,role:$role,invocation_id:$invocation_id,attempt_id:$attempt_id,run_id:$id,verdict:"error",effective_status:"error",
      observation_count:1,usage_state:"unknown",accounting:{tokens:null,total_tokens:null,input_tokens:null,cached_input_tokens:null,output_tokens:null,reasoning_output_tokens:null,token_state:"unknown",usage_state:"unknown",cost_usd:null,cost_amount:null,cost_currency:null,cost_state:"unknown",cost_provenance:"unknown",pricing:null,allocation:null,runtime_cost:null,unclassified_runtime_cost:null},issues:[{severity:"error",attribution:$attribution,summary:$reason}]}' \
    > "$OBSERVATION_SUMMARY"
  jq -n --arg id "$RUN_ID" --arg scenario "$SCENARIO_ID" --arg runtime "$RUNTIME" --arg program_id "$PROGRAM_ID" --arg issue_id "$ISSUE_ID" --arg phase "$PHASE" --arg role "$ROLE" --arg invocation_id "$INVOCATION_ID" --arg attempt_id "$RUN_ATTEMPT_ID" --arg current_sha "$EARLY_SHA" \
    --arg model "$MODEL" --arg reason "$REASON" --arg observations "$OBSERVATIONS" \
    --arg observation_summary "$OBSERVATION_SUMMARY" --slurpfile completeness "$OBSERVATION_SUMMARY" \
    '{schema_version:"1.0",run_id:$id,scenario:$scenario,runtime:$runtime,model:$model,
      status:"error",exit_status:null,current_sha:$current_sha,reviewed_sha:"unknown",observation_verdict:"error",reason:$reason,duration_ms:0,program_id:$program_id,issue_id:$issue_id,phase:$phase,invocation_id:$invocation_id,attempt_id:$attempt_id,role:$role,verified_outcome:null,usage:{tokens:null,total_tokens:null,input_tokens:null,cached_input_tokens:null,output_tokens:null,reasoning_output_tokens:null,token_state:"unknown",usage_state:"unknown",cost_usd:null,cost_amount:null,cost_currency:null,cost_state:"unknown",cost_provenance:"unknown",pricing:null,allocation:null,runtime_cost:null,unclassified_runtime_cost:null},
      artifacts:{observations:$observations,observation_summary:$observation_summary},
      observation_completeness:$completeness[0]}' > "$RUN_RECORD"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --runtime) RUNTIME=${2:-}; shift 2 ;;
    --scenario) SCENARIO=${2:-}; shift 2 ;;
    --runs) RUNS=${2:-}; shift 2 ;;
    --model) MODEL=${2:-}; shift 2 ;;
    --reasoning) REASONING=${2:-}; shift 2 ;;
    --phase) PHASE=${2:-}; shift 2 ;;
    --role) ROLE=${2:-}; shift 2 ;;
    --program-id) PROGRAM_ID=${2:-}; shift 2 ;;
    --issue-id) ISSUE_ID=${2:-}; shift 2 ;;
    --attempt-id) ATTEMPT_ID=${2:-}; shift 2 ;;
    --outcome-id) OUTCOME_ID=${2:-}; shift 2 ;;
    --subject-attempt-id) SUBJECT_ATTEMPT_ID=${2:-}; shift 2 ;;
    --judge) JUDGE=${2:-}; shift 2 ;;
    --judge-model) JUDGE_MODEL=${2:-}; shift 2 ;;
    --timeout) TIMEOUT_OVERRIDE=${2:-}; shift 2 ;;
    --results-dir) RESULTS_DIR=${2:-}; shift 2 ;;
    --mock-mode) MOCK_MODE=${2:-}; shift 2 ;;
    --keep-workspaces) KEEP_WORKSPACES=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

case "$RUNTIME" in claude|codex|opencode|mock) ;; *) usage; exit 2 ;; esac
[ -n "$SCENARIO" ] || { usage; exit 2; }
case "$RUNS" in ''|*[!0-9]*) usage; exit 2 ;; esac
[ "$RUNS" -gt 0 ] || { usage; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "eval runner requires jq" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { echo "eval runner requires python3" >&2; exit 3; }

if [ -z "$RESULTS_DIR" ]; then
  RESULTS_DIR="$ROOT/evals/results/$(date -u +%Y%m%dT%H%M%SZ)-$RUNTIME"
fi
mkdir -p "$RESULTS_DIR" "$ROOT/evals/scratch"
RESULTS_DIR=$(cd "$RESULTS_DIR" && pwd)
INVOCATION_ID=${HARNESS_INVOCATION_ID:-"$(date -u +%Y%m%dT%H%M%SZ)-$$"}

if [ "$SCENARIO" = all ]; then
  SCENARIOS=()
  for MANIFEST in "$ROOT"/evals/scenarios/*/manifest.json; do
    [ -f "$MANIFEST" ] || continue
    CANDIDATE_DIR=$(dirname "$MANIFEST")
    CANDIDATE_SEMANTIC=$(jq -r '.semantic_required // false' "$MANIFEST" 2>/dev/null || echo false)
    if [ -x "$CANDIDATE_DIR/setup.sh" ] && [ -x "$CANDIDATE_DIR/grade.sh" ] && [ -f "$CANDIDATE_DIR/prompt.md" ] \
      && { [ "$CANDIDATE_SEMANTIC" != true ] || [ -f "$CANDIDATE_DIR/rubric.md" ]; }; then
      SCENARIOS+=("$(basename "$CANDIDATE_DIR")")
    else
      echo "skipping incomplete scenario (missing setup.sh/grade.sh/prompt.md, or rubric.md for a semantic scenario): $(basename "$CANDIDATE_DIR")" >&2
    fi
  done
else
  SCENARIOS=("$SCENARIO")
fi

if [ ${#SCENARIOS[@]} -eq 0 ]; then
  echo "no scenarios matched (nothing under evals/scenarios/*/manifest.json is complete enough to run)" >&2
  exit 3
fi

RUN_RECORDS=()
for SCENARIO_ID in "${SCENARIOS[@]}"; do
  SCENARIO_DIR="$ROOT/evals/scenarios/$SCENARIO_ID"
  [ -f "$SCENARIO_DIR/manifest.json" ] || { echo "unknown scenario: $SCENARIO_ID" >&2; exit 2; }
  TIMEOUT=$(jq -r '.timeout_seconds' "$SCENARIO_DIR/manifest.json")
  [ -z "$TIMEOUT_OVERRIDE" ] || TIMEOUT=$TIMEOUT_OVERRIDE

  for ((INDEX=1; INDEX<=RUNS; INDEX++)); do
    RUN_ID="$SCENARIO_ID-$RUNTIME-$INDEX"
    RUN_ATTEMPT_ID=${ATTEMPT_ID:-"$INVOCATION_ID:$RUN_ID"}
    RUN_DIR="$RESULTS_DIR/$RUN_ID"
    SCRATCH_DIR=$(mktemp -d "$ROOT/evals/scratch/$RUN_ID.XXXXXX")
    WORKSPACE="$SCRATCH_DIR/workspace"
    mkdir -p "$WORKSPACE" "$RUN_DIR"
    TRACE="$RUN_DIR/events.jsonl"
    HOOK_TRACE="$RUN_DIR/hook-events.jsonl"
    WORK_TRACE="$WORKSPACE/.eval/results/events.jsonl"
    DRIVER_RECORD="$RUN_DIR/driver.json"
    BEFORE_DIFF="$RUN_DIR/before.diff"
    AFTER_DIFF="$RUN_DIR/after.diff"
    GRADE="$RUN_DIR/grade.json"
    JUDGE_RECORD="$RUN_DIR/judge.json"
    RUN_RECORD="$RUN_DIR/run.json"
    OBSERVATIONS="$RUN_DIR/observations.v1.jsonl"
    OBSERVATION_SUMMARY="$RUN_DIR/observations.v1.summary.json"

    (cd "$WORKSPACE" && "$SCENARIO_DIR/setup.sh")
    SETUP_STATUS=$?
    if [ "$SETUP_STATUS" -ne 0 ]; then
      write_early_failure product "scenario setup failed"
      RUN_RECORDS+=("$RUN_RECORD")
      cleanup_scratch
      continue
    fi

    if ! "$ROOT/evals/lib/install-harness.sh" "$ROOT" "$WORKSPACE" "$RUNTIME"; then
      write_early_failure harness "harness installation failed"
      RUN_RECORDS+=("$RUN_RECORD")
      cleanup_scratch
      continue
    fi
    mkdir -p "$(dirname "$WORK_TRACE")"
    : > "$WORK_TRACE"
    FROZEN_SHA=$(git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null || printf '%s' unknown)
    git -C "$WORKSPACE" diff HEAD --binary > "$BEFORE_DIFF"

    FORBIDDEN_PATHS=$(jq -c '.forbidden_paths // []' "$SCENARIO_DIR/manifest.json")
    FORBIDDEN_BEFORE=$(fingerprint_forbidden "$WORKSPACE" "$FORBIDDEN_PATHS")

    DRIVER="$ROOT/evals/drivers/$RUNTIME.sh"
    HARNESS_ROOT="$ROOT" HARNESS_WORKSPACE="$WORKSPACE" HARNESS_SCENARIO="$SCENARIO_ID" \
      HARNESS_PROMPT_FILE="$SCENARIO_DIR/prompt.md" HARNESS_TRACE_FILE="$WORK_TRACE" \
      HARNESS_RUN_DIR="$RUN_DIR" HARNESS_DRIVER_RECORD="$DRIVER_RECORD" \
      HARNESS_MODEL="$MODEL" HARNESS_REASONING="$REASONING" HARNESS_TIMEOUT="$TIMEOUT" HARNESS_MOCK_MODE="$MOCK_MODE" \
      "$DRIVER"
    DRIVER_STATUS=$?

    cp "$WORK_TRACE" "$HOOK_TRACE"
    TRANSCRIPT=$(jq -r '.transcript // empty' "$DRIVER_RECORD" 2>/dev/null || true)
    if [ -n "$TRANSCRIPT" ] && python3 "$ROOT/evals/lib/normalize_transcript.py" "$RUNTIME" "$TRANSCRIPT" "$TRACE" "$WORKSPACE" "$HOOK_TRACE"; then
      :
    else
      cp "$HOOK_TRACE" "$TRACE"
    fi

    git -C "$WORKSPACE" diff HEAD --binary > "$AFTER_DIFF"
    CURRENT_SHA=$(git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null || printf '%s' unknown)
    FORBIDDEN_AFTER=$(fingerprint_forbidden "$WORKSPACE" "$FORBIDDEN_PATHS")
    if [ "$FORBIDDEN_BEFORE" = "$FORBIDDEN_AFTER" ]; then FORBIDDEN_HIT=false; else FORBIDDEN_HIT=true; fi
    "$SCENARIO_DIR/grade.sh" "$WORKSPACE" "$TRACE" "$BEFORE_DIFF" > "$GRADE"
    GRADE_STATUS=$?
    [ "$GRADE_STATUS" -eq 0 ] && jq -e '.deterministic_pass | type == "boolean"' "$GRADE" >/dev/null 2>&1 || \
      jq -n '{checks:{grader_valid:false},deterministic_pass:false}' > "$GRADE"

    if ! jq -e 'type == "object" and (.runtime | type == "string")' "$DRIVER_RECORD" >/dev/null 2>&1; then
      jq -n --arg runtime "$RUNTIME" --argjson exit_status "$DRIVER_STATUS" \
        '{runtime:$runtime,model:"unknown",exit_status:$exit_status,duration_ms:0,usage:{tokens:null,total_tokens:null,input_tokens:null,cached_input_tokens:null,output_tokens:null,reasoning_output_tokens:null,cost_usd:null,token_state:"unknown",cost_state:"unknown",cost_provenance:"unknown"},malformed:true}' > "$DRIVER_RECORD"
    fi

    SEMANTIC_REQUIRED=$(jq -r '.semantic_required' "$SCENARIO_DIR/manifest.json")
    if [ "$SEMANTIC_REQUIRED" = true ]; then
      if [ "$JUDGE" = none ]; then
        jq -n '{status:"needs_review",reason:"This scenario requires semantic rubric grading and no judge was requested."}' > "$JUDGE_RECORD"
      else
        "$ROOT/evals/judge.sh" "$JUDGE" "$SCENARIO_DIR" "$RUN_DIR" "$DRIVER_RECORD" "$JUDGE_RECORD" "$JUDGE_MODEL" "$TIMEOUT"
      fi
    else
      jq -n '{status:"not_required",reason:"Deterministic evidence is sufficient for this scenario."}' > "$JUDGE_RECORD"
    fi

    CHANGED_PATHS=$( { git -C "$WORKSPACE" diff --name-only --no-renames -z HEAD; git -C "$WORKSPACE" ls-files --others --exclude-standard -z; } \
      | jq -Rsc 'split("\u0000") | map(select(length > 0)) | unique')

    DETERMINISTIC=$(jq -r '.deterministic_pass' "$GRADE")
    JUDGE_STATUS=$(jq -r '.status' "$JUDGE_RECORD")
    EXIT_STATUS=$(jq -r '.exit_status' "$DRIVER_RECORD")
    MALFORMED=$(jq -r '.malformed // false' "$DRIVER_RECORD")
    if [ "$FORBIDDEN_HIT" = true ]; then STATUS=fail
    elif [ "$MALFORMED" = true ]; then STATUS=error
    elif [ "$EXIT_STATUS" -eq 127 ]; then STATUS=unavailable
    elif [ "$EXIT_STATUS" -eq 124 ]; then STATUS=timeout
    elif [ "$EXIT_STATUS" -ne 0 ]; then STATUS=error
    elif [ "$DETERMINISTIC" != true ]; then STATUS=fail
    elif [ "$JUDGE_STATUS" = fail ]; then STATUS=fail
    elif [ "$JUDGE_STATUS" = needs_review ]; then STATUS=needs_review
    else STATUS=pass
    fi

    OBSERVATION_SOURCE="$TRACE"
    if [ "$RUNTIME" = codex ] && [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
      OBSERVATION_SOURCE="$TRANSCRIPT"
    fi
    if [ -f "$ROOT/evals/lib/build_observations.py" ] && [ -f "$ROOT/evals/lib/accounting.py" ] && python3 "$ROOT/evals/lib/build_observations.py" \
      --runtime "$RUNTIME" --transcript "$OBSERVATION_SOURCE" --hooks "$HOOK_TRACE" \
      --driver "$DRIVER_RECORD" --run-id "$RUN_ID" --phase "$PHASE" --role "$ROLE" \
      --reasoning "$REASONING" --frozen-sha "$FROZEN_SHA" --current-sha "$CURRENT_SHA" \
      --diff "$AFTER_DIFF" --phase-status "$STATUS" --output "$OBSERVATIONS" \
      --summary "$OBSERVATION_SUMMARY" --program-id "$PROGRAM_ID" --issue-id "$ISSUE_ID" \
      --attempt-id "$RUN_ATTEMPT_ID"; then
      STATUS=$(jq -r '.effective_status' "$OBSERVATION_SUMMARY")
    elif [ ! -f "$ROOT/evals/lib/build_observations.py" ] || [ ! -f "$ROOT/evals/lib/accounting.py" ]; then
      # A consumer can safely receive this run.sh before the later core-module sync.
      # Keep its legacy run/status behavior and make the missing accounting explicit.
      jq -n --arg id "$RUN_ID" --arg program_id "$PROGRAM_ID" --arg issue_id "$ISSUE_ID" --arg phase "$PHASE" --arg role "$ROLE" \
        --arg invocation_id "$INVOCATION_ID" --arg attempt_id "$RUN_ATTEMPT_ID" --arg status "$STATUS" \
        '{schema_version:"observations.v1",program_id:$program_id,issue_id:$issue_id,phase:$phase,role:$role,invocation_id:$invocation_id,attempt_id:$attempt_id,run_id:$id,verdict:"unknown",effective_status:$status,observation_count:0,usage_state:"unknown",accounting:{tokens:null,total_tokens:null,input_tokens:null,cached_input_tokens:null,output_tokens:null,reasoning_output_tokens:null,token_state:"unknown",usage_state:"unknown",cost_usd:null,cost_amount:null,cost_currency:null,cost_state:"unknown",cost_provenance:"unknown",pricing:null,allocation:null,runtime_cost:null,unclassified_runtime_cost:null},issues:[{severity:"warning",attribution:"harness",summary:"accounting core modules absent; consumer sync required"}]}' \
        > "$OBSERVATION_SUMMARY"
      : > "$OBSERVATIONS"
    else
      write_early_failure harness "observation builder failed"
      RUN_RECORDS+=("$RUN_RECORD")
      echo "$RUN_ID: error"
      cleanup_scratch
      continue
    fi

    TOOL_EVIDENCE=$(jq -s '
      {event_count:length,
       tool_counts:(map(select(.event != null) | (.tool_name // .event)) | group_by(.) | map({key:.[0],value:length}) | from_entries),
       checks:(map(select(.record_type == "check")) | length)}
    ' "$TRACE" 2>/dev/null || printf '%s' '{"event_count":0,"tool_counts":{},"checks":0}')

    DECISION=$(python3 - "$RUN_DIR/final.md" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    lines = path.read_text(errors="replace").splitlines()
except OSError:
    print("unknown")
    raise SystemExit
nonblank = [line for line in lines if line.strip()]
markers = [line for line in nonblank if line.startswith("VERDICT:")]
if len(markers) != 1 or not nonblank or markers[0] != nonblank[-1]:
    print("unknown")
else:
    match = re.fullmatch(r"VERDICT: (READY|NO-GO)", markers[0])
    print(match.group(1) if match else "unknown")
PY
)
    EVIDENCE_PATHS=("$DRIVER_RECORD" "$OBSERVATION_SUMMARY")
    [ ! -f "$RUN_DIR/final.md" ] || EVIDENCE_PATHS+=("$RUN_DIR/final.md")
    FILE_EVIDENCE=$(python3 - "${EVIDENCE_PATHS[@]}" <<'PY'
import hashlib
import json
import sys
from pathlib import Path
print(json.dumps([{"basename": Path(name).name, "sha256": hashlib.sha256(Path(name).read_bytes()).hexdigest()} for name in sys.argv[1:]], separators=(",", ":"), allow_nan=False))
PY
)
    OBSERVATION_VERDICT=$(jq -r '.verdict // "unknown"' "$OBSERVATION_SUMMARY")
    jq -n --arg id "$RUN_ID" --arg scenario "$SCENARIO_ID" --arg status "$STATUS" --arg reasoning "$REASONING" \
      --arg program_id "$PROGRAM_ID" --arg issue_id "$ISSUE_ID" --arg phase "$PHASE" --arg invocation_id "$INVOCATION_ID" --arg attempt_id "$RUN_ATTEMPT_ID" --arg role "$ROLE" --arg outcome_id "$OUTCOME_ID" --arg subject_attempt_id "$SUBJECT_ATTEMPT_ID" --arg current_sha "$CURRENT_SHA" --arg observation_verdict "$OBSERVATION_VERDICT" --arg decision "$DECISION" \
      --arg workspace "$WORKSPACE" --arg trace "$TRACE" --arg hook_trace "$HOOK_TRACE" --arg before "$BEFORE_DIFF" --arg after "$AFTER_DIFF" \
      --argjson driver "$(cat "$DRIVER_RECORD")" --argjson grade "$(cat "$GRADE")" --argjson forbidden_hit "$FORBIDDEN_HIT" \
      --argjson judge "$(cat "$JUDGE_RECORD")" --argjson changed "$CHANGED_PATHS" --argjson evidence "$TOOL_EVIDENCE" --argjson file_evidence "$FILE_EVIDENCE" '
      {schema_version:"1.0",program_id:$program_id,issue_id:$issue_id,phase:$phase,invocation_id:$invocation_id,attempt_id:$attempt_id,run_id:$id,role:$role,scenario:$scenario,status:$status,
       runtime:$driver.runtime,model:$driver.model,reasoning_level:($driver.reasoning_level // $reasoning),
       runtime_version:($driver.cli_version // "unknown"),harness_sha:($driver.harness_sha // "unknown"),
       exit_status:$driver.exit_status,current_sha:$current_sha,reviewed_sha:(if $outcome_id == "" then "unknown" else $current_sha end),observation_verdict:$observation_verdict,decision:$decision,duration_ms:$driver.duration_ms,
       source_artifacts:$file_evidence,
       verified_outcome:(if $outcome_id != "" and $subject_attempt_id != "" and $decision == "READY" and $status == "pass" and $driver.exit_status == 0 and $observation_verdict == "pass" and ($role == "reviewer" or $role == "verifier") then {outcome_id:$outcome_id,verification_id:$attempt_id,verifier_role:$role,subject_attempt_id:$subject_attempt_id,terminal_status:"pass",reviewed_sha:$current_sha,decision:$decision,evidence:$file_evidence} else null end),
       outcome_claim_status:(if $outcome_id == "" then "not_requested" elif $subject_attempt_id != "" and $decision == "READY" and $status == "pass" and $driver.exit_status == 0 and $observation_verdict == "pass" and ($role == "reviewer" or $role == "verifier") then "accepted" else "rejected" end),
       reason:($driver.reason // null),usage:$driver.usage,tool_evidence:$evidence,checks:$grade.checks,semantic_judge:$judge,
       changed_paths:$changed,forbidden_path_hit:$forbidden_hit,artifacts:{workspace:$workspace,trace:$trace,hook_trace:$hook_trace,before_diff:$before,after_diff:$after,
       transcript:($driver.transcript // null),final:($driver.final // null)}}
    ' > "$RUN_RECORD"
    jq --arg observations "$OBSERVATIONS" --arg observation_summary "$OBSERVATION_SUMMARY" \
      --slurpfile completeness "$OBSERVATION_SUMMARY" \
      '.artifacts.observations=$observations | .artifacts.observation_summary=$observation_summary | .observation_completeness=$completeness[0]' \
      "$RUN_RECORD" > "$RUN_RECORD.tmp" && mv "$RUN_RECORD.tmp" "$RUN_RECORD"
    RUN_RECORDS+=("$RUN_RECORD")
    echo "$RUN_ID: $STATUS"
    cleanup_scratch
  done
done

if [ ${#RUN_RECORDS[@]} -eq 0 ]; then
  echo "no run records were produced; refusing to run jq -s with zero file operands (would hang reading stdin)" >&2
  exit 3
fi

jq -s '
  {schema_version:"1.0",total:length,
   by_status:(group_by(.status) | map({key:.[0].status,value:length}) | from_entries),
   pass_rate:(if length == 0 then 0 else ([.[] | select(.status == "pass")] | length) / length end),
   runtimes:(group_by([.runtime,.model,.reasoning_level]) | map({runtime:.[0].runtime,model:.[0].model,
     reasoning_level:(.[0].reasoning_level // "unknown"),runtime_version:(.[0].runtime_version // "unknown"),runs:length,
     passed:([.[] | select(.status == "pass")] | length),duration_ms:(map(.duration_ms // 0) | add),
     tokens:(map(.usage.tokens) | if any(.[]; . == null) then null elif length == 0 then null else add end),
     cost_usd:null})),
   runs:map({program_id,issue_id,phase,invocation_id,attempt_id,run_id,role,decision,verified_outcome,outcome_claim_status,scenario,runtime,model,status,exit_status,current_sha,reviewed_sha,duration_ms,tool_evidence,usage,forbidden_path_hit,
     observation_verdict:(.observation_completeness.verdict // "missing")})}
' "${RUN_RECORDS[@]}" > "$RESULTS_DIR/summary.json"

if [ -f "$ROOT/evals/lib/accounting.py" ]; then
  if ! python3 "$ROOT/evals/lib/accounting.py" --output "$RESULTS_DIR/accounting.json" "${RUN_RECORDS[@]}"; then
    echo "accounting aggregation failed" >&2
    exit 1
  fi
  jq --slurpfile accounting "$RESULTS_DIR/accounting.json" '.accounting=$accounting[0]' \
    "$RESULTS_DIR/summary.json" > "$RESULTS_DIR/summary.json.tmp" && mv "$RESULTS_DIR/summary.json.tmp" "$RESULTS_DIR/summary.json"
else
  jq '.accounting={schema_version:"accounting.v1",state:"legacy_unknown",reason:"accounting core module absent; sync lib/accounting.py and lib/build_observations.py"}' \
    "$RESULTS_DIR/summary.json" > "$RESULTS_DIR/summary.json.tmp" && mv "$RESULTS_DIR/summary.json.tmp" "$RESULTS_DIR/summary.json"
fi

echo "results: $RESULTS_DIR/summary.json"
