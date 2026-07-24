# Cursor adapter

Wires the portable `hooks/` policies into [Cursor Agent hooks](https://cursor.com/docs/agent/hooks)
(`.cursor/hooks.json`, `version: 1`). Cursor is a first-class runtime: its native
payloads are normalized to protocol `1.0` by `normalize.sh`, exactly like Codex/Claude.

## Why Cursor is a clean fit

Cursor honors **exit code `2` = deny** (equivalent to returning `permission: "deny"`),
so the policies' native exit codes flow straight through `run-hook.sh` — no
permission-JSON translation is needed for edits or commands. `failClosed: true` on the
safety hooks makes an unexpected hook failure block rather than fall open.

## Event mapping

| Harness event | Cursor hook | Policies | Blocks? |
|---|---|---|---|
| `pre_command` | `beforeShellExecution` | guard-destructive, guard-worktree | yes (exit 2) |
| `pre_edit` | `preToolUse` (matcher `Write\|Edit\|MultiEdit`) | guard-secrets, guard-protected-paths, guard-worktree | yes (exit 2) |
| `post_edit` | `afterFileEdit` | post-edit-format | no (formatting only) |
| `stop` | `stop` → `cursor/stop-gate.sh` | stop-verify-gate | continues via `followup_message` |

Unlike the review's initial assumption, Cursor **can** block an edit *before* it lands:
`preToolUse` fires before the `Write`/`Edit` tool and supports `permission: deny`. So
secrets/protected-paths/worktree are enforced pre-write, not just detected after.

`stop` is the one event that doesn't use an exit code — Cursor continues the agent when
the hook prints `{"followup_message": "..."}`. `cursor/stop-gate.sh` runs the portable
verify-gate and emits that message on a red `.harness/check`.

## Install

```sh
cp .harness/adapters/cursor/hooks.json .cursor/hooks.json     # merge if one exists
cp -R .harness/adapters/cursor/rules/. .cursor/rules/          # contract pointer (.mdc)
chmod +x .harness/adapters/run-hook.sh .harness/adapters/cursor/*.sh .harness/hooks/*.sh
```

`aios harness install` does this (and the merge) for you.

## Honest limitations / thin spots

- **`afterFileEdit` carries no `cwd`** and cannot block (the edit already landed); it is
  used only for non-blocking formatting. `cwd` falls back to `${CURSOR_PROJECT_DIR:-$PWD}`.
- **`preToolUse` `tool_input` shape** for the built-in edit tools is normalized
  defensively (`file_path` / `path` / `target_file`, and `content` / joined
  `edits[].new_string`). If a future Cursor build renames those fields, `pre_edit`
  path/content extraction may miss — the `afterFileEdit` formatter and the
  `pre-commit`/`pre-merge-commit` git-hooks remain as backstops. Confirmed against the
  documented payloads as of 2026-07.
- **`stop` recursion**: `verification_loop_active` is derived from `loop_count > 0`;
  pair with Cursor's own `loop_limit` in `hooks.json` for a hard ceiling.
