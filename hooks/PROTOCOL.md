# Portable hook event protocol

Protocol `1.0` is the boundary between runtime adapters and portable policy. Runtime
adapters normalize their native payloads to one JSON object on stdin; scripts in
`hooks/` must not parse Claude Code, Codex, or OpenCode payloads directly.

Common fields are `protocol_version`, `event`, `runtime.name`, `cwd`, and optional
`session_id`, `tool_name`, and `tool_id`. Event fields are:

| Event | Required fields |
|---|---|
| `pre_edit` | `paths[]`, `added_content[]` (content introduced by the edit only) |
| `pre_command` | `command` |
| `post_edit` | `paths[]` |
| `stop` | `stop.verification_loop_active` |

Each path has an `action` (`add`, `update`, `delete`, `rename`, or `unknown`). A rename
uses the destination as `path` and the source as `from`. The normative machine shape
is [`protocol.schema.json`](protocol.schema.json).

Portable scripts have three outcomes: `0` allows, `2` is a policy block, and `3`
means the event or local configuration could not be evaluated. Safety adapters map
`3` to a native block. Post-edit formatting always maps failures to allow.

Direct Claude-shaped input to the top-level hook scripts remains supported for the
v0 migration window. New installations must invoke the Claude adapter. Direct
runtime-shaped parsing inside policy is deprecated and Codex/OpenCode payloads are
accepted only by their adapters.

Set `HARNESS_TRACE_FILE` to capture normalized JSONL evidence. The file must be under
a directory named `scratch` or `results`; tracing is off by default. Trace records may
contain command or added-content evidence, so they are evaluation artifacts and must
not be committed.
