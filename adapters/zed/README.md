# Adapter — Zed (via ACP)

[Zed](https://zed.dev) is the cleanest way to run this harness *inside an editor*
without changing the harness at all. Zed's [Agent Client Protocol (ACP)](https://zed.dev/acp)
makes the editor a thin client: Zed hosts the thread UI, and the **external agent keeps
its own runtime, auth, model, tools — and therefore this pack's skills, hooks, and
settings**. You are not adopting a new harness; you're giving your existing one an
editor surface.

## Why this combination is interesting

- **The harness travels with the agent, not the editor.** Run Claude Code as Zed's
  external agent and everything in this pack applies unchanged — guards still block,
  skills still fire, the stop-gate still gates. Zero porting.
- **Agent following:** Zed's crosshair mode jumps the editor to each file the agent
  reads/edits — a cheap, high-trust supervision affordance for engineers on rungs 1–2
  of the [autonomy ladder](../../docs/autonomy-ladder.md) (you *see* what it touches).
- **AGENTS.md is native** in Zed, so the contract layer works for Zed's own agent too.
- **One protocol, many agents:** the ACP registry lists Claude Code, Codex CLI, Copilot
  CLI, opencode, Gemini CLI, and others — a team can standardize on this pack while
  individuals pick their runtime (the tool-pluralist rollout pattern).

## Try it (10 minutes)

1. Install Zed (`brew install --cask zed` on macOS) and open a repo that has the pack
   installed (`.claude/` populated per `adapters/claude-code/`).
2. Open the Agent Panel (✨ icon, or `cmd-?`), then **+ → your external agent** —
   Claude Code appears as an available external agent (Zed manages the ACP adapter;
   first run installs it). For other agents: `zed: acp registry` from the command
   palette.
3. Sign-in happens through the agent's own auth (`/login` in the thread for Claude
   Code) — Zed never proxies your credentials.
4. Run a task. Verify the harness is live from inside Zed:
   - ask it to write to `.env` → `guard-protected-paths` must block;
   - `/plan-first` etc. are available since skills live in the repo/user scope, not in
     the editor.
5. Turn on the crosshair ("agent following") and watch the file-level attention.

## Configuration notes

- Zed's `settings.json` (`agent_servers`) lets you register custom/ACP agents with an
  explicit command — useful for pinned versions or a bulk-lane profile:

```json
{
  "agent_servers": {
    "Claude Code (bulk lane)": {
      "command": "claude",
      "args": [],
      "env": { "ANTHROPIC_BASE_URL": "…", "ANTHROPIC_AUTH_TOKEN": "…" }
    }
  }
}
```

  (Same lane discipline as everywhere: bulk-lane sessions get frontier review before
  merge — rubric MG6.)
- Hooks execute in the agent's process, exactly as in the terminal. The only
  Claude-Code feature without a Zed surface today is interactive plan-mode toggling —
  drive it with `/plan-first` + explicit instructions instead.

## Verdict

ACP is the interoperability seam this pack bets on for editor integration (see
PROVENANCE — "target the standards, not a runtime's plugin API"). Treat Zed as the
reference ACP client; anything else that speaks ACP (JetBrains, etc.) inherits the same
setup.
