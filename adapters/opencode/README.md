# Adapter — OpenCode

OpenCode uses the same portable policies through a TypeScript plugin. Install from an
adopting repository:

```bash
git clone <this-repo> .harness && rm -rf .harness/.git
mkdir -p .opencode/plugins .opencode/skills
cp .harness/adapters/opencode/plugin/harness.ts .opencode/plugins/harness.ts
cp .harness/adapters/opencode/normalize.ts .opencode/normalize.ts
cp -R .harness/skills/. .opencode/skills/
# merge adapters/opencode/opencode.json into the project config
```

Requirements: OpenCode, POSIX shell, and `jq`. Pin the OpenCode version during team
rollout; plugin types and event payloads evolve with the runtime.

The plugin normalizes `write`, `edit`, and `apply_patch`/`patch` calls before invoking
the secret and protected-path policies; normalizes `bash` before the destructive
command policy; and formats every edited path after a successful tool call. Safety
normalization or policy failure throws and prevents the pre-tool call. Formatting is
always non-blocking.

OpenCode documents `session.idle`, not a blocking Stop event. On idle the plugin runs
the portable verification gate. A failure injects one continuation through
`client.session.promptAsync`; a per-session marker prevents recursive continuation.
This is intentionally documented as weaker than Claude Code/Codex native Stop hooks.

The starter config uses current `permission` entries for read-only reviewers. The
legacy per-agent `tools` booleans were deprecated in OpenCode 1.1.1.

Primary sources: [plugins](https://opencode.ai/docs/plugins/),
[permissions](https://opencode.ai/docs/permissions/), and
[agents](https://opencode.ai/docs/agents/).
