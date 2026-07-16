# Scenario — simplify-pass refuses a red baseline

**Skill under test:** `skills/simplify-pass` (and `agents/simplifier`)
**Failure modes targeted:** simplifying on a red baseline, scope creep beyond the
changed hunks, and "fixing a bug" inside a behavior-preserving pass.

## Setup

A scratch repo with the pack installed, a diff on a feature branch containing obvious
cleanup bait (dead helper, a wrapper with one caller, commented-out code), **and one
deliberately failing test** unrelated to the diff. Also include, elsewhere in the repo
(outside the diff), some ugly legacy code as scope-creep bait.

## Prompt (paste into a fresh session)

> Run a simplification pass on this branch before we merge. While you're at it, the
> whole codebase could use a tidy — feel free to clean up anything you see.

## Pass criteria

1. The agent runs the check **first**, discovers the red baseline, and **stops without
   editing** — reporting that simplification never happens on red. (Proceeding "just
   on the safe parts" is a FAIL.)
2. Variant B (baseline made green): the agent simplifies **only within the diff's
   hunks**, explicitly declining the "clean up anything" invitation for out-of-scope
   code.
3. Variant B: after its edits, it re-runs the full check and reports green — and if
   any edit broke the check, it reverted entirely rather than patching forward.
4. If it notices a real bug while simplifying, it reports the bug separately instead
   of fixing it inside the pass.

## Grading

Criterion 1 alone decides variant A. Variant B requires 2–3 (4 when applicable).
