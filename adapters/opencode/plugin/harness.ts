import type { Plugin } from "@opencode-ai/plugin"
import { existsSync } from "node:fs"
import { join } from "node:path"
import { spawnSync } from "node:child_process"
import { normalizeStopEvent, normalizeToolEvent, type NormalizedEvent } from "../normalize"

const HOOK_TIMEOUT_MS = 10_000

function runScript(root: string, script: string, event: NormalizedEvent) {
  const result = spawnSync("/bin/sh", [join(root, "hooks", script)], {
    cwd: event.cwd,
    input: JSON.stringify(event),
    encoding: "utf8",
    env: process.env,
    timeout: HOOK_TIMEOUT_MS,
  })
  return {
    status: result.status ?? 3,
    reason: (result.stderr || result.error?.message || "").trim(),
  }
}

function trace(root: string, policy: string, event: NormalizedEvent, outcome: number) {
  if (!process.env.HARNESS_TRACE_FILE) return 0
  const result = spawnSync("/bin/sh", [join(root, "hooks", "trace-event.sh"), policy, String(outcome)], {
    cwd: event.cwd,
    input: JSON.stringify(event),
    encoding: "utf8",
    env: process.env,
    timeout: HOOK_TIMEOUT_MS,
  })
  return result.status ?? 3
}

export const HarnessGuards: Plugin = async ({ client, directory, worktree }) => {
  const candidate = process.env.HARNESS_ROOT || join(worktree, ".harness")
  const root = existsSync(join(candidate, "hooks", "protocol.schema.json")) ? candidate : worktree
  const continued = new Set<string>()

  const enforce = (policy: string, event: NormalizedEvent, formatting = false) => {
    const result = runScript(root, policy, event)
    const traceStatus = trace(root, policy, event, result.status)
    if (formatting) return
    if (traceStatus !== 0) throw new Error("Harness trace configuration failed")
    if (result.status === 2) throw new Error(result.reason || `Blocked by ${policy}`)
    if (result.status !== 0) throw new Error(result.reason || `${policy} could not evaluate the event`)
  }

  return {
    "tool.execute.before": async (input, output) => {
      const tool = input.tool.toLowerCase()
      if (["write", "edit", "apply_patch", "patch"].includes(tool)) {
        let event: NormalizedEvent
        try {
          event = normalizeToolEvent("pre_edit", { ...input, tool }, output.args, directory)
        } catch (error) {
          throw new Error(`Harness edit normalization failed: ${(error as Error).message}`)
        }
        enforce("guard-secrets.sh", event)
        enforce("guard-protected-paths.sh", event)
      } else if (tool === "bash") {
        let event: NormalizedEvent
        try {
          event = normalizeToolEvent("pre_command", { ...input, tool }, output.args, directory)
        } catch (error) {
          throw new Error(`Harness command normalization failed: ${(error as Error).message}`)
        }
        enforce("guard-destructive.sh", event)
      }
    },

    "tool.execute.after": async (input) => {
      const tool = input.tool.toLowerCase()
      if (!["write", "edit", "apply_patch", "patch"].includes(tool)) return
      try {
        const event = normalizeToolEvent("post_edit", { ...input, tool }, input.args, directory)
        enforce("post-edit-format.sh", event, true)
      } catch {
        // Formatting is intentionally non-blocking, including normalization failure.
      }
    },

    event: async ({ event }) => {
      if (event.type !== "session.idle") return
      const sessionID = event.properties.sessionID
      const loop = continued.has(sessionID)
      // The second idle event is the terminal verification attempt. Do not pass
      // the recursion flag to the hook, because that flag intentionally skips
      // verification and would turn a still-red check into a false success.
      const normalized = normalizeStopEvent(directory, sessionID, false)
      const result = runScript(root, "stop-verify-gate.sh", normalized)
      const traceStatus = trace(root, "stop-verify-gate.sh", normalized, result.status)

      if (result.status === 0 && traceStatus === 0) {
        continued.delete(sessionID)
        return
      }
      if (loop) {
        continued.delete(sessionID)
        const reason =
          traceStatus !== 0
            ? "The harness verification trace still could not be recorded after one continuation."
            : result.status === 2
              ? result.reason || "The harness verification gate is still red after one continuation."
              : result.reason || "The harness verification gate still could not be evaluated after one continuation."
        throw new Error(reason)
      }

      continued.add(sessionID)
      const reason =
        result.status === 2
          ? result.reason
          : "The harness verification gate could not be evaluated. Diagnose the adapter or dependency failure before reporting completion."
      await client.session.promptAsync({
        path: { id: sessionID },
        query: { directory },
        body: { parts: [{ type: "text", text: reason }] },
      })
    },
  }
}
