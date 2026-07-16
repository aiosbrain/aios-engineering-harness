# Thin spots — what this pack is honest about

v0 is four weeks of curation distilled into a usable pack. These are the places where
it is still thin, unproven, or deliberately deferred — read this before treating any
component as battle-tested. (Curation-with-provenance cuts both ways: we cite where
patterns came from, and we tell you where ours haven't been pressure-tested yet.)

## Thin (shipped, but young)

- **The hooks are new code.** The *patterns* are proven (they're adapted from guards
  running in production in the AIOS toolkit and from disler's hook repos), but these
  specific scripts have unit-level testing only (synthetic payloads), not months of
  field time. Expect to tune the destructive-command regexes to your team's habits.
- **The opencode and Codex adapters are mappings, not shipped installs.** The
  Claude Code adapter is the reference path; the other two document how the pieces map
  and include starter config, but haven't been run end-to-end on a real team repo.
- **`models/routing.yaml` is a convention, not an engine.** Nothing enforces the lane
  policy mechanically yet — MG6 (bulk output needs frontier review) is enforced by
  rubric + process. The category-routing pattern it encodes is proven elsewhere
  (oh-my-opencode, Amp); our YAML contract for it is new.
- **No eval suite.** The pack asserts its skills change agent behavior; obra-style
  pressure-testing (`skill-author` describes it) has been applied ad hoc, not as a
  maintained eval battery with regression tracking. This is the biggest credibility gap
  vs. the state of the art (Hamel Husain would not approve — yet).

## Deferred (deliberately not in v0)

- **The pipeline CLI.** A tracker-agnostic `plan → build → review → simplify → PR` loop
  (one command per stage, worktree-isolated, fail-closed gates) exists in the AIOS
  toolkit (`aios build/ship/spec/simplify/consolidate-findings`) but is coupled to its
  workspace + Linear conventions. Extracting it as a standalone CLI is the headline V1
  item — v0 ships the methodology (skills/rubrics/agents) that the CLI automates.
- **Rung 4 / unattended loops (Ralph).** Powerful and real (see PROVENANCE), but only
  safe behind sandbox + comprehensive tests + rollback + cost caps, all four. We'd
  rather ship the ladder that earns it than the loop that skips it.
- **Durable agent memory (Beads-style issue graph).** Compatible add-on; adopting it is
  an infrastructure decision a team should make deliberately, not a default.
- **GAR / governed-autonomy runtime.** Mechanical enforcement of the autonomy ladder
  (rung tracked per work-category, gates that move the leash automatically on
  evidence). Today the ladder is process + hooks; the runtime is roadmap.
- **CI-side enforcement.** The same guards and review gates as a CI stage (so the rules
  hold for humans and agents alike, and for agents running outside the harness).
  Today: local hooks + branch protection.
- **Team Brain / telemetry integration.** Plugging harness activity (lanes used,
  escapes, ladder movement) into a shared team surface. Roadmap, tied to the AIOS
  workspace ecosystem this pack grew out of.

## Known trade-offs

- **Hooks require `bash` + `jq`** and fail *open* (with a stderr note) when `jq` is
  missing — chosen so a missing dependency can't brick a session, at the cost that a
  stripped environment silently loses guard coverage. Check your environment once:
  `command -v jq`.
- **The stop-verify-gate allows the stop on the second consecutive failure** (loop
  protection) — an agent can still end a session with a red check, but only after the
  failure output is in the transcript twice and flagged "do not report as done."
- **Portability over power.** By targeting the shared standards we forgo
  runtime-specific strengths (Claude Code plugins/marketplaces, opencode's TS plugin
  depth, Codex's kernel sandbox as policy). The adapters note where each runtime can
  do better than the portable baseline.
