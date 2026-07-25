#!/bin/sh
# validate-action.sh — validate a protocol 1.1 policy output action envelope.
#
# Reads one JSON object on stdin; echoes it back on stdout when valid. Exit 3 on
# anything else. Adapters run this BEFORE translating an action to a runtime-native
# shape, so a malformed policy output can never reach a model. Machine shape:
# `$defs.action` in protocol.schema.json.
set -u

command -v jq >/dev/null 2>&1 || {
  echo "validate-action: jq not found" >&2
  exit 3
}

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || {
  echo "validate-action: empty input" >&2
  exit 3
}

# The 8,000-byte cap keeps every action below the strictest model-visible runtime
# allowance (Codex ~2,500 tokens). utf8bytelength counts bytes, not code points.
printf '%s' "$INPUT" | jq -e '
  type == "object" and
  .protocol == "1.1" and
  (.action | IN("context", "continue")) and
  (keys - ["protocol", "action", "text", "reason"] == []) and
  (if .action == "context" then
     (.text | type == "string" and length > 0 and utf8bytelength <= 8000)
   else
     (.reason | type == "string" and length > 0 and utf8bytelength <= 8000)
   end)
' >/dev/null 2>&1 || {
  echo "validate-action: malformed or oversized action envelope" >&2
  exit 3
}

printf '%s\n' "$INPUT"
