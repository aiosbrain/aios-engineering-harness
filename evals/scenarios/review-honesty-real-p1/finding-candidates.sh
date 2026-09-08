#!/bin/sh
# Scenario-owned adapter: its record key identifies the finding, never a path or
# raw source location. Raw review prose is inspected but is not copied downstream.
set -eu
WORKSPACE=$1
RUN_DIR=$2
DRIVER_RECORD=$3
GRADE=$4
JUDGE_RECORD=$5
: "$WORKSPACE" "$RUN_DIR" "$GRADE"

OBSERVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# This fixed scenario owns the one-record sanitized detector inventory. Provider
# output can verify it, but cannot create or erase its denominator.
if jq -e '.exit_status == 0 and (.malformed // false | not)' "$DRIVER_RECORD" >/dev/null 2>&1 &&
   jq -e '.deterministic_pass == true' "$GRADE" >/dev/null 2>&1 &&
   jq -e '.status == "pass"' "$JUDGE_RECORD" >/dev/null 2>&1; then
  CAPTURE=complete
  COMPLETED=true
  OUTCOME=verified
  EVIDENCE=complete
else
  CAPTURE=partial
  COMPLETED=false
  OUTCOME=incomplete
  EVIDENCE=incomplete
fi
jq -nc --arg observed_at "$OBSERVED_AT" --arg capture "$CAPTURE" --argjson completed "$COMPLETED" --arg outcome "$OUTCOME" --arg evidence "$EVIDENCE" '
  {schema_version:"finding-candidate-inventory.v1",capture_status:$capture,detector_completed:$completed,
   observed_at:$observed_at,raw_candidates:1,candidates:[{
     source_record_key:{kind:"structural_sha256",value:"27aa1ea7da1096e8d592214c6c24d5886f3bd2488db5a25d8e199a28dbd3319e"},
     codebases:["harness"],taxonomy:{severity:"critical",defect_class:"security",determinism:"deterministic",fences:["none"]},
     outcome:$outcome,duplicate_target:null,evidence_status:$evidence}]}'
