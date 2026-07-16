# Adapter — opencode

[opencode](https://opencode.ai) consumes most of this pack natively; what Claude Code
calls hooks maps to opencode's permission config + plugins.

## What maps directly

| Pack component | opencode equivalent |
|---|---|
| `AGENTS.md`, `CONSTITUTION.md` | `instructions` array (see `opencode.json` here) |
| `skills/` | opencode skills — same `SKILL.md` format; place under `.opencode/skill/` |
| `agents/*.md` | custom agents — reference the same markdown as `prompt: {file:...}` (see `opencode.json`) |
| `models/routing.yaml` lanes | per-agent `model:` settings — `plan` on the frontier lane, `build` on the bulk lane |
| Permission rails | `permission` block (`allow`/`ask`/`deny` per tool/command pattern) |

## What needs the plugin layer

The three guard hooks and the stop-gate are shell scripts driven by Claude Code's hook
protocol. On opencode, enforce the same rules via:

1. **Permission config first** (zero code): the `deny`/`ask` patterns in `opencode.json`
   cover destructive commands; protected paths can be expressed as edit-permission
   patterns.
2. **A small plugin** for what config can't express (secrets scan on write, the
   stop-verify gate): opencode plugins are TypeScript with lifecycle hooks
   (`tool.execute.before`, session events) — wrap the existing shell scripts:

```ts
// .opencode/plugin/harness-guards.ts
import { spawnSync } from "node:child_process"
export const HarnessGuards = async () => ({
  "tool.execute.before": async (input, output) => {
    if (["write", "edit"].includes(input.tool)) {
      const r = spawnSync("bash", [".harness/hooks/guard-secrets.sh"], {
        input: JSON.stringify({ tool_name: input.tool, tool_input: output.args }),
      })
      if (r.status === 2) throw new Error(r.stderr.toString())
    }
  },
})
```

(Same pattern for `guard-protected-paths.sh`; run `stop-verify-gate.sh` from a
session-idle/end event.)

## Version pinning (learned the hard way)

opencode ships fast and breaks things; harnesses built on it inherit that churn. **Pin
the opencode version** (and any plugin pack like oh-my-opencode to a release tag, with
telemetry disabled) — never track `latest` on a team rollout.
