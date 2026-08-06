#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="$ROOT/adapters/run-hook.sh"
PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
SCOPE="$TMP/guarded"
OUTSIDE="$TMP/outside"
XDG="$TMP/config"
mkdir -p "$SCOPE/nested" "$OUTSIDE" "$XDG/aios"
jq -n --arg scope "$SCOPE" '{schemaVersion:1,defaultWorkspace:$scope,guardScopes:[$scope]}' > "$XDG/aios/config.json"

check() {
  local name=$1 want=$2 runtime=$3 payload=$4
  printf '%s' "$payload" | XDG_CONFIG_HOME="$XDG" "$ADAPTER" "$runtime" pre_tool guard-linear-routing.sh >/dev/null 2>&1
  local got=$?
  if [ "$got" -eq "$want" ]; then
    PASS=$((PASS+1)); printf 'PASS (%s): %s\n' "$got" "$name"
  else
    FAIL=$((FAIL+1)); printf 'FAIL (got %s, want %s): %s\n' "$got" "$want" "$name"
  fi
}

claude() { jq -cn --arg cwd "$1" --arg tool "$2" --arg command "${3:-}" \
  '{cwd:$cwd,session_id:"s1",tool_name:$tool,tool_input:{command:$command}}'; }
codex() { jq -cn --arg cwd "$1" --arg tool "$2" --arg command "${3:-}" \
  '{cwd:$cwd,session_id:"s1",tool_name:$tool,tool_input:{command:$command}}'; }
cursor() { jq -cn --arg cwd "$1" --arg tool "$2" --arg command "${3:-}" \
  '{cwd:$cwd,conversation_id:"s1",tool_name:$tool,tool_input:{command:$command}}'; }

for runtime in claude-code codex cursor; do
  case "$runtime" in
    claude-code) event() { claude "$@"; } ;;
    codex) event() { codex "$@"; } ;;
    cursor) event() { cursor "$@"; } ;;
  esac
  check "$runtime allows aios linear in scope" 0 "$runtime" "$(event "$SCOPE/nested" Bash 'aios linear list --json')"
  check "$runtime blocks direct Linear API in scope" 2 "$runtime" "$(event "$SCOPE" Bash 'curl https://api.linear.app/graphql')"
  check "$runtime blocks copied Linear script in scope" 2 "$runtime" "$(event "$SCOPE" Bash 'node /tmp/linear.mjs list')"
  check "$runtime leaves non-AIOS projects unaffected" 0 "$runtime" "$(event "$OUTSIDE" Bash 'curl https://api.linear.app/graphql')"
  check "$runtime leaves unrelated commands unaffected" 0 "$runtime" "$(event "$SCOPE" Bash 'git status')"
  check "$runtime blocks Linear MCP mutations" 2 "$runtime" "$(event "$SCOPE" mcp__linear__create_issue '')"
  check "$runtime allows Linear MCP reads" 0 "$runtime" "$(event "$SCOPE" mcp__linear__get_issue '')"
done

COMPOUND=$(claude "$SCOPE" Bash 'aios linear list; curl https://api.linear.app/graphql')
check "first-party route cannot hide a compound direct call" 2 claude-code "$COMPOUND"

ROUTE=$(jq -cn --arg cwd "$SCOPE" '{cwd:$cwd,session_id:"s1",prompt:"Please create a Linear issue"}')
OUT=$(printf '%s' "$ROUTE" | XDG_CONFIG_HOME="$XDG" "$ADAPTER" claude-code user_prompt_submit route-aios-linear.sh 2>/dev/null)
if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | contains("aios-linear")' >/dev/null 2>&1; then
  PASS=$((PASS+1)); echo "PASS (0): Linear prompt routes to aios-linear"
else
  FAIL=$((FAIL+1)); echo "FAIL: Linear prompt did not route to aios-linear"
fi

OUT=$(printf '%s' "$(jq -cn --arg cwd "$OUTSIDE" '{cwd:$cwd,session_id:"s1",prompt:"Please create a Linear issue"}')" \
  | XDG_CONFIG_HOME="$XDG" "$ADAPTER" claude-code user_prompt_submit route-aios-linear.sh 2>/dev/null)
if [ -z "$OUT" ]; then
  PASS=$((PASS+1)); echo "PASS (0): non-AIOS Linear prompt is unaffected"
else
  FAIL=$((FAIL+1)); echo "FAIL: non-AIOS Linear prompt was routed"
fi

printf 'linear-routing.test.sh: %s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
