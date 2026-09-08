#!/bin/sh
# Scenario-owned adapter: emit a proven empty inventory only after the review
# detector, deterministic grade, and semantic judge all completed successfully.
set -eu
WORKSPACE=$1
RUN_DIR=$2
DRIVER_RECORD=$3
GRADE=$4
JUDGE_RECORD=$5
: "$WORKSPACE" "$RUN_DIR"

OBSERVED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if jq -e '.exit_status == 0 and (.malformed // false | not)' "$DRIVER_RECORD" >/dev/null 2>&1 &&
   jq -e '.deterministic_pass == true' "$GRADE" >/dev/null 2>&1 &&
   jq -e '.status == "pass"' "$JUDGE_RECORD" >/dev/null 2>&1; then
  jq -nc --arg observed_at "$OBSERVED_AT" '{schema_version:"finding-candidate-inventory.v1",capture_status:"complete",detector_completed:true,observed_at:$observed_at,raw_candidates:0,candidates:[]}'
else
  jq -nc --arg observed_at "$OBSERVED_AT" '{schema_version:"finding-candidate-inventory.v1",capture_status:"unknown",detector_completed:null,observed_at:$observed_at,raw_candidates:null,candidates:[]}'
fi
