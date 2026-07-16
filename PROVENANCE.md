# Provenance

Every component in this pack is curated from the published practice of working agentic
engineers or from battle-tested open-source packs, then adapted to be stack- and
runtime-agnostic. This file is the map. `AM` columns reference the open Agentic Maturity
pattern library (patterns A1–E5).

## Components → sources

| Component | Curated from | AM pattern | Notes on adaptation |
|---|---|---|---|
| `AGENTS.md` template (slow facts, <200 lines, error-ledger) | Boris Cherny — [How Boris Uses Claude Code](https://howborisusesclaudecode.com/); the [AGENTS.md standard](https://agents.md); Amp's "AGENTS.md for slow facts, MCP for live facts" split ([ampcode.com](https://ampcode.com)) | A1, A2 | Merged the error-ledger convention with the cross-tool standard. |
| `CONSTITUTION.md` (pinned principles + machine-read digest) | AIOS toolkit `ENGINEERING-CONSTITUTION.md` (itself adapted from [GitHub Spec Kit](https://github.com/github/spec-kit)'s Spec-Driven Development) | B3, E5 | Generalized: AIOS-specific domain rules removed; digest-injection convention kept. |
| `skills/plan-first` | Dex Horthy's RPI — [advanced context engineering](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents); Cherny's plan-mode-first habit | B1, B3 | Adds the 40–60% context-utilization discipline and plan-as-source-of-truth review point. |
| `skills/tdd-fail-first` | Jesse Vincent (obra) — [Superpowers](https://github.com/obra/superpowers) enforced TDD | B2, B4 | RED-GREEN-REFACTOR with the fail-first proof step; runner-agnostic. |
| `skills/systematic-debugging` | Superpowers four-phase debugging | B4 | Root-cause before fix; generalized commands. |
| `skills/simplify-pass` | Boris Cherny's code-simplifier subagent habit; AIOS `aios simplify` | C7 | Behavior-preserving, check-gated, revert-on-failure. |
| `skills/code-review` | Kieran Klaassen — [compound engineering](https://every.to/guides/compound-engineering) parallel review; AIOS `consolidate-findings` (fail-closed severity fusion) | C3, D4 | Fresh-context reviewer + P1/P2/P3 triage. |
| `skills/verify-change` | "Give it a check it can run" — the consensus pattern (Anthropic docs, Willison, AM B2) | B2 | Drive the real flow, not just the tests. |
| `skills/compound-learnings` | Klaassen's compound step; Mitchell Hashimoto's mistake→guardrail reflex ([Zed interview](https://zed.dev/blog/agentic-engineering-with-mitchell-hashimoto)) | A1, C1 | The closing step of every task: codify or it didn't compound. |
| `skills/skill-author` | Superpowers' skill-writing skill; Anthropic skill-authoring guidance | C1 | Includes obra's pressure-testing idea: stress a draft skill against realistic scenarios before trusting it. |
| `skills/branch-reconciliation` | AIOS toolkit skill (born from a real audit where ~80% of "stale" branches were squash-merge duplicates) | B5 | Evidence-based, classify-only. |
| `skills/test-ci-wiring-audit` | AIOS toolkit skill (born from finding tests wired into neither `npm test` nor CI) | B2, C8 | Generalized beyond npm to any runner/CI. |
| `hooks/guard-secrets.sh` | AIOS `team-ops-guard.sh`; standard secret-pattern sets | C4 | Pattern file externalized so teams extend it. |
| `hooks/guard-destructive.sh` | IndyDevDan — [claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery); Anthropic destructive-op confirmation practice | C4, B6 | Blocks `rm -rf`, force-push, hard reset, etc. outside an allowlist. |
| `hooks/guard-protected-paths.sh` | Hooks-as-enforcement consensus ("never edit .env" as a *guarantee*) | C4 | Path denylist: env files, lockfiles, migrations, CI config — configurable. |
| `hooks/post-edit-format.sh` | Cherny (hooks auto-format); Hashimoto | C4 | Detects the repo's formatter; no-ops gracefully. |
| `hooks/stop-verify-gate.sh` | AM B2 ladder ("a stop hook that blocks until the check passes") | B2, C4 | The leash-lengthener: agent can't declare done while the check fails. |
| `agents/code-reviewer` | Writer/reviewer split (AM C3 — a fresh session catches more); compound engineering's review agents | C3 | |
| `agents/adversarial-verifier` | AIOS spec-eval refute-style evaluator; AM B7 adversarial prompting | B7, D4 | Verdict-gated; tries to refute, not confirm. |
| `agents/security-reviewer` | compound engineering's specialized panel | C3, D2 | |
| `agents/simplifier` | Cherny's simplifier subagent | C7 | |
| `rubrics/spec-readiness.md` | AIOS `.claude/rubrics/spec-readiness.md` (two-layer deterministic + adversarial model) | B3, D3 | AIOS-specific criteria removed; the "cold-start builder can pick this up" test kept. |
| `rubrics/code-review.md` | consolidated multi-reviewer practice (AIOS `consolidate-findings`, fail-closed severity) | D4 | |
| `models/routing.yaml` | oh-my-opencode's category-based delegation ([omo.dev](https://omo.dev)); Amp's Oracle/Worker split & no-model-picker philosophy; [cc-compatible-models](https://github.com/Alorse/cc-compatible-models) wiring | E1, B6 | Categories → model + fallback chain; frontier reserved for plan/review/merge. |
| `docs/autonomy-ladder.md` | AM maturity spine + "earn the leash" (E5); Anthropic guardrails practice; sandbox tier ladder (devcontainer → worktree → microVM) | B6, E5 | The team-rollout story. |
| `docs/adopt-any-stack.md` | Armin Ronacher's stack-agnostic recommendations ([lucumr](https://lucumr.pocoo.org/2025/6/12/agentic-coding/)); AGENTS.md field practice | A1, E3 | |

## Practitioners this pack is distilled from

Simon Willison · Armin Ronacher · Geoffrey Huntley · Peter Steinberger · Thorsten Ball ·
Boris Cherny · Mitchell Hashimoto · Dex Horthy · Jesse Vincent · Kieran Klaassen ·
Steve Yegge · Hamel Husain · Andrej Karpathy (framing) · the Anthropic engineering team —
plus the AIOS toolkit's own shipped harness (`aios build/relay/spec/simplify/rails`),
where several of these patterns were first hardened for our own use.

## Deliberately not included (and why)

- **The Ralph loop** (Geoffrey Huntley's unattended while-loop) — powerful, but only safe
  behind a sandbox + strong tests + rollback. Documented as a gated future module in
  [docs/thin-spots.md](docs/thin-spots.md), not shipped default-on.
- **Heavy orchestration frameworks** (claude-flow, Gas Town, agent fleets) — overkill for
  a core pack; adopt only if you truly run fleets.
- **Beads** (Yegge's issue-graph agent memory) — excellent, but an infrastructure choice
  a team should make deliberately; noted as a compatible add-on.
- **Any single runtime's plugin API** — the pack targets the portable standards instead.
