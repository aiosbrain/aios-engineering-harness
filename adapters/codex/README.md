# Adapter — OpenAI Codex CLI

Codex CLI reads the same portable surfaces this pack is built on.

## What maps directly

| Pack component | Codex equivalent |
|---|---|
| `AGENTS.md` | native — repo root `AGENTS.md` (plus `~/.codex/AGENTS.md` global) |
| `CONSTITUTION.md` | reference it from `AGENTS.md` ("read CONSTITUTION.md's agent-digest before any task") |
| `skills/` | Codex skills — same `SKILL.md` shape; install under `~/.agents/skills/` (user) or the repo's skills dir |
| `agents/*.md` | Codex subagents (TOML-defined) — port the markdown body as the subagent's instructions |
| `models/routing.yaml` | `model`/profile config; Codex profiles per lane |

## What Codex gives you for free

- **OS-level sandboxing** (Seatbelt on macOS, Bubblewrap on Linux): file-write and
  network constraints enforced by the kernel, with an approval flow to cross the
  boundary. This overlaps with `guard-destructive.sh` / `guard-protected-paths.sh` —
  keep the sandbox as the outer wall and treat the pack's guards as the portable,
  fine-grained layer (they express *repo policy*, not just isolation).

## What doesn't map yet

- The Stop-hook verify gate has no direct Codex equivalent — encode the same rule as
  process instead: the final instruction of every task prompt is "run `<check>`; if it
  fails you are not done." Weaker than a hook (advisory, not guaranteed); note it in
  your rollout as a known gap.
- `post-edit-format.sh` → rely on your formatter's pre-commit hook instead
  (`pre-commit`, husky, lefthook) — which is good practice on every runtime anyway.
