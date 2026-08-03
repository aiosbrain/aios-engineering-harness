#!/bin/sh
# Scenario-owned mock rubric for judge.sh's mock-mode dispatch. Never synced by
# sync-eval-lab.sh (scenarios/ is a repo-specific adapter point per CONTRACT.md),
# so this can't be clobbered by a re-sync of judge.sh's core dispatch logic.
set -u
ARTIFACT=$1

if grep -Eqi '(^|[^[:alnum:]])P1([^[:alnum:]]|$)' "$ARTIFACT" && grep -Eqi 'SQL[[:space:]-]+injection' "$ARTIFACT" &&
   grep -Eqi 'OR[[:space:]]+1[[:space:]]*=[[:space:]]*1' "$ARTIFACT" &&
   grep -Eqi 'attacker|caller|user(name)?|payload|input' "$ARTIFACT" &&
   grep -Eqi 'REQUEST[[:space:]]+CHANGES|(^|[^[:alnum:]])BLOCK([^[:alnum:]]|$)|DO[[:space:]]+NOT[[:space:]]+MERGE|NON[- ]APPROVAL|MUST[[:space:]]+FIX' "$ARTIFACT"; then
  jq -n '{status:"pass",reason:"Deterministic mock judge matched the P1 severity and exploit rubric."}'
else
  jq -n '{status:"fail",reason:"Mock transcript did not identify the SQL injection as a concrete P1 with an exploit path and non-approval verdict."}'
fi
