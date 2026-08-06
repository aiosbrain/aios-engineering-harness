export type PathChange = {
  path: string
  action: "add" | "update" | "delete" | "rename" | "unknown"
  from?: string
}

export type NormalizedEvent = {
  protocol_version: "1.0" | "1.1" | "1.2"
  event: "pre_edit" | "pre_command" | "pre_tool" | "post_edit" | "stop" | "session_start" | "subagent_start" | "user_prompt_submit"
  runtime: { name: "opencode" }
  cwd: string
  session_id: string
  tool_name?: string
  tool_id?: string
  paths?: PathChange[]
  added_content?: Array<{ path: string; content: string }>
  command?: string
  operation?: "read" | "mutation" | "execute" | "unknown"
  tool_input?: Record<string, string>
  stop?: {
    verification_loop_active: boolean
    stop_status?: "ok" | "failed" | "aborted" | "error"
    loop_count?: number
  }
  session_start?: { phase: "startup" | "resume" | "compact" }
  subagent_start?: { agent_type?: string; agent_id?: string }
  prompt?: string
}

type ToolInput = { tool: string; sessionID: string; callID: string }

function parsePatch(patch: string) {
  const paths: PathChange[] = []
  const added_content: Array<{ path: string; content: string }> = []
  let current = ""

  for (const line of patch.split("\n")) {
    const header = line.match(/^\*\*\* (Add|Update|Delete) File: (.*)$/)
    if (header) {
      current = header[2]
      paths.push({
        path: current,
        action: header[1].toLowerCase() as "add" | "update" | "delete",
      })
      continue
    }
    const move = line.match(/^\*\*\* Move to: (.*)$/)
    if (move) {
      if (!current || !move[1]) throw new Error("OpenCode patch rename has no source or destination")
      const from = current
      current = move[1]
      paths.splice(paths.length - 1, 1, { path: current, action: "rename", from })
      continue
    }
    if (line.startsWith("+") && !line.startsWith("+++")) {
      added_content.push({ path: current || "<unknown>", content: line.slice(1) })
    }
  }
  return { paths, added_content }
}

function stringArg(args: Record<string, unknown>, ...names: string[]) {
  for (const name of names) {
    if (typeof args[name] === "string") return args[name] as string
  }
  return ""
}

function toolOperation(tool: string): "read" | "mutation" | "execute" | "unknown" {
  if (/create|update|delete|archive|comment|assign|relation|set.state/i.test(tool)) return "mutation"
  if (/read|get|list|search|find/i.test(tool)) return "read"
  if (/bash|shell|exec|http|fetch/i.test(tool)) return "execute"
  return "unknown"
}

export function normalizePreToolEvent(
  input: ToolInput,
  args: Record<string, unknown>,
  cwd: string,
): NormalizedEvent {
  const fields: Record<string, string> = {}
  const aliases: Array<[string, string[]]> = [
    ["command", ["command", "cmd"]],
    ["url", ["url", "uri"]],
    ["method", ["method"]],
    ["server", ["server", "serverName"]],
    ["name", ["name", "tool"]],
    ["operation_name", ["operation_name", "operationName"]],
  ]
  for (const [target, names] of aliases) {
    const value = stringArg(args, ...names)
    if (value) fields[target] = value.slice(0, 16384)
  }
  return {
    protocol_version: "1.2",
    event: "pre_tool",
    runtime: { name: "opencode" },
    cwd,
    session_id: input.sessionID,
    tool_name: input.tool,
    tool_id: input.callID,
    operation: toolOperation(input.tool),
    tool_input: fields,
  }
}

export function normalizeToolEvent(
  event: "pre_edit" | "pre_command" | "post_edit",
  input: ToolInput,
  args: Record<string, unknown>,
  cwd: string,
): NormalizedEvent {
  const base = {
    protocol_version: "1.0" as const,
    event,
    runtime: { name: "opencode" as const },
    cwd,
    session_id: input.sessionID,
    tool_name: input.tool,
    tool_id: input.callID,
  }

  if (event === "pre_command") {
    const command = stringArg(args, "command", "cmd")
    if (!command) throw new Error("OpenCode bash payload has no command")
    return { ...base, command }
  }

  if (["apply_patch", "patch"].includes(input.tool)) {
    const parsed = parsePatch(stringArg(args, "patch", "patchText", "command"))
    if (!parsed.paths.length) throw new Error("OpenCode patch payload has no paths")
    return event === "pre_edit"
      ? { ...base, ...parsed }
      : { ...base, paths: parsed.paths }
  }

  const path = stringArg(args, "filePath", "file_path", "path")
  if (!path) throw new Error("OpenCode edit payload has no path")
  const action = input.tool === "write" ? "add" : "update"
  const paths: PathChange[] = [{ path, action }]
  if (event === "post_edit") return { ...base, paths }
  const content = stringArg(args, "content", "newString", "new_string")
  return { ...base, paths, added_content: [{ path, content }] }
}

export function normalizeStopEvent(
  cwd: string,
  sessionID: string,
  loop: boolean,
  loopCount?: number,
): NormalizedEvent {
  return {
    protocol_version: "1.0",
    event: "stop",
    runtime: { name: "opencode" },
    cwd,
    session_id: sessionID,
    stop: {
      verification_loop_active: loop,
      stop_status: "ok",
      loop_count: loopCount ?? (loop ? 1 : 0),
    },
  }
}

export function normalizeUserPromptEvent(cwd: string, sessionID: string, prompt: string): NormalizedEvent {
  return {
    protocol_version: "1.1",
    event: "user_prompt_submit",
    runtime: { name: "opencode" },
    cwd,
    session_id: sessionID,
    prompt,
  }
}

export function normalizeSessionStartEvent(
  cwd: string,
  sessionID: string,
  phase: "startup" | "resume" | "compact",
): NormalizedEvent {
  return {
    protocol_version: "1.1",
    event: "session_start",
    runtime: { name: "opencode" },
    cwd,
    session_id: sessionID,
    session_start: { phase },
  }
}
