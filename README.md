# AIOS Engineering Harness

A curated, drop-in harness for **agentic software engineering** — the skills, hooks,
guards, subagent definitions, verification rubrics, and model-routing conventions that
make coding agents produce production-grade work on any stack (TypeScript, PHP, Python,
Go, …) under any of the major agent runtimes (Claude Code first; opencode and Codex CLI
via adapters).

**This is a curation-and-synthesis project, not an invention.** Every component cites
where it came from — the practicing agentic engineers and open-source packs whose
patterns have actually survived contact with production. See [PROVENANCE.md](PROVENANCE.md)
for the full component → source map, and [docs/thin-spots.md](docs/thin-spots.md) for an
honest account of what is still early or unproven.

> Status: **v0 — early, rough, usable.** Four weeks of open-source harness work distilled
> into a pack you can read in twenty minutes and adopt in an afternoon.

## The idea in one paragraph

Models are commoditizing; **the harness is where engineering quality lives**. An agent
with a strong model but no harness produces plausible code fast and debt faster. The fix
is not more prompting — it's *structure*: a plan the human reviews before code exists, a
check the agent can run itself, guards that make rules enforceable rather than advisory,
an adversarial review pass that isn't biased toward code it just wrote, and a compounding
step that turns every mistake into a permanent guardrail. Each of those is a component in
this pack.

## What's in the box

| Layer | Where | What it does |
|---|---|---|
| **Contracts** | [`AGENTS.md`](AGENTS.md) · [`CONSTITUTION.md`](CONSTITUTION.md) | The repo↔agent contract (slow facts, conventions, error-ledger) and the pinned engineering principles with a machine-readable digest agents ingest every session. |
| **Skills** | [`skills/`](skills/) | Ten curated methodology skills — plan-first, fail-first TDD, systematic debugging, verification, post-review simplification, compounding learnings, and a skill that writes new skills. Portable `SKILL.md` format (Claude Code, Codex, opencode). |
| **Hooks & guards** | [`hooks/`](hooks/) | Enforcement, not suggestion: secrets guard, destructive-command guard, protected-path guard, format-on-edit, and a stop-gate that blocks "done" until the check passes. |
| **Subagents** | [`agents/`](agents/) | The review panel: fresh-context code reviewer, adversarial verifier, security reviewer, behavior-preserving simplifier. |
| **Rubrics** | [`rubrics/`](rubrics/) | Machine-checkable readiness criteria — a spec-readiness gate (is this plan pick-up-able by a cold-start agent?) and a code-review grading sheet. Verdict-gated, refute-style. |
| **Model routing** | [`models/routing.yaml`](models/routing.yaml) | Category-based multi-model delegation: a frontier lane for planning/review/merge, a bulk lane (e.g. GLM), a cheap utility lane — with fallback chains. Route by capability tier, never expose a model picker. |
| **Adapters** | [`adapters/`](adapters/) | Wiring for Claude Code (`settings.json`, hooks, permission rails), opencode, Codex CLI, and Zed (via ACP — the harness inside an editor, unchanged). |
| **Evals** | [`evals/`](evals/) | The harness verifying itself: a 42-case deterministic battery for the guards (`guards.test.sh`) plus behavioral pressure-test scenarios for the core skills. |
| **Optional modules** | [`modules/`](modules/) | Opt-in batteries the core never depends on: the AIOS CLI (loop engineering + Team Brain), agentic-maturity self-assessment, cost monitoring, context-hygiene monitoring. |
| **Docs** | [`docs/`](docs/) | [Adopt on any stack](docs/adopt-any-stack.md) · [The autonomy ladder](docs/autonomy-ladder.md) (how a team rolls this out *safely*) · [Thin spots](docs/thin-spots.md). |

## The maturity model behind it

This pack is the executable companion to the open **Agentic Maturity** framework — a
5-level spine (Prompting → Prompt Engineering → Context Engineering → Agentic Engineering
→ Agentic Orchestration), five cross-cutting axes (verification, context hygiene,
autonomy, learning, cost/governance), and a library of 24 named patterns distilled from
the field's best practitioners. Every component here is tagged with the AM pattern it
implements (`am_pattern:` in its frontmatter) and the maturity level it unlocks.

That matters for teams: you don't adopt a harness by switching everything on. You place
each engineer on the ladder, adopt the components that unlock their next level, and
lengthen the autonomy leash only as verification strengthens. **You don't climb to
autonomy — you earn it through verification.** See
[docs/autonomy-ladder.md](docs/autonomy-ladder.md).

## Quickstart (Claude Code)

```bash
# from your repo root
git clone <this-repo> .harness   # or vendor the directories you want
cp -r .harness/skills .claude/skills
cp -r .harness/agents .claude/agents
cp -r .harness/hooks .harness-hooks && chmod +x .harness-hooks/*.sh
# merge .harness/adapters/claude-code/settings.json into .claude/settings.json
cp .harness/AGENTS.md ./AGENTS.md          # then fill in the TODOs for your stack
cp .harness/CONSTITUTION.md ./CONSTITUTION.md
```

Then, in a Claude Code session: `/plan-first` on your next non-trivial task, and watch
the guards fire. Full per-stack instructions (including PHP/Python examples and the
opencode/Codex paths): [docs/adopt-any-stack.md](docs/adopt-any-stack.md).

## Design principles

1. **Portable over powerful.** Components are markdown + POSIX shell targeting the shared
   standards (AGENTS.md, SKILL.md, MCP) — not any one runtime's plugin API. Runtimes
   churn; the pack survives.
2. **Enforcement over instruction.** Anything that must happen every time is a hook, not
   a sentence in a prompt.
3. **Verification is the value.** Every autonomy increase is paid for with a stronger
   check. Non-frontier model output always passes a review gate.
4. **Compounding.** The harness gets better every time it's used: mistakes become
   guardrails, solutions become skills, corrections become AGENTS.md lines.
5. **Cited, honest, small.** Provenance on everything, thin spots documented, and no
   component you can't read in one sitting.

## License

MIT — see [LICENSE](LICENSE).
