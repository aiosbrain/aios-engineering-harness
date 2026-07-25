#!/bin/sh
set -u

command -v jq >/dev/null 2>&1 || {
  echo "validate-event: jq not found" >&2
  exit 3
}

INPUT=$(cat 2>/dev/null || true)
[ -n "$INPUT" ] || {
  echo "validate-event: empty input" >&2
  exit 3
}

printf '%s' "$INPUT" | jq -e '
  type == "object" and
  .protocol_version == "1.0" and
  (.event | IN("pre_edit", "pre_command", "post_edit", "stop")) and
  (.runtime | type == "object") and
  (.runtime.name | IN("claude", "codex", "opencode", "cursor", "mock")) and
  (.cwd | type == "string" and length > 0) and
  (if .event == "pre_edit" then
     (.paths | type == "array" and length > 0) and
     (.added_content | type == "array") and
     (all(.paths[]; (.path | type == "string" and length > 0) and
       (.action | IN("add", "update", "delete", "rename", "unknown")))) and
     (all(.added_content[]; (.path | type == "string" and length > 0) and
       (.content | type == "string")))
   elif .event == "pre_command" then
     (.command | type == "string" and length > 0)
   elif .event == "post_edit" then
     (.paths | type == "array" and length > 0) and
     all(.paths[]; (.path | type == "string" and length > 0) and
       (.action | IN("add", "update", "delete", "rename", "unknown")))
   else
     (.stop | type == "object") and
     (.stop.verification_loop_active | type == "boolean")
   end)
' >/dev/null 2>&1 || {
  echo "validate-event: malformed or unsupported protocol event" >&2
  exit 3
}

printf '%s\n' "$INPUT"
