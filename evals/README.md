# Evals

Verification is the value — including for the harness itself. This directory is the
pack's own eval layer: does each component actually do what it claims, and does it keep
doing it as it changes? (Approach per Hamel Husain's eval discipline and AM D3
eval-driven development: start deterministic and cheap, grow toward behavioral evals
from real failures, never let a component's claim outrun its evidence.)

## Layer 1 — deterministic (shipped, runnable)

[`guards.test.sh`](guards.test.sh) — the regression battery for the five hooks:
42 synthetic blocked/allowed tool-call payloads covering secrets, protected paths,
destructive commands, the stop-gate (including loop protection), and the formatter's
never-block contract.

```bash
bash evals/guards.test.sh    # exit 0 = green; run before any change to hooks/ merges
```

Two rules keep it honest:
- **Every field-found guard bug adds a case here** before the fix merges (this is
  `compound-learnings` applied to the harness itself — the battery has already caught
  two real bugs: an `rm -rf /` regex gap and a grep-option injection via patterns
  starting with `-`).
- Secret-like fixtures are assembled at runtime by concatenation, so the test file
  itself never trips a secret scanner.

## Layer 2 — behavioral scenarios (shipped, agent-run)

[`scenarios/`](scenarios/) — pressure-test scripts for the methodology skills, per the
obra technique: put a *fresh* agent (with the skill installed) into a realistic
situation where the easy path violates the skill, and grade what it does. Each scenario
file states the setup, the temptation, and the pass/fail criteria; an
`adversarial-verifier` (or a human) grades the transcript.

Run one: start a fresh session in a scratch repo with the pack installed, paste the
scenario's **Prompt**, then grade against its **Pass criteria**. Automating this loop
(N runs per scenario, pass-rate tracking over time) is the next step — see below.

## Layer 3 — not built yet (honest)

- **Pass-rate tracking:** scenarios run manually today; no harness runs them N times
  and trends the results. This is the highest-value next build.
- **Skill-trigger evals:** does each skill fire on the phrasings in its description
  and stay quiet otherwise? Testable cheaply with a matrix of task prompts.
- **End-to-end lane evals:** the routing table's claim (bulk lane + frontier review ≥
  frontier-only quality at lower cost) is measurable on a fixed task set — currently
  it's an argument, not a result.

The bar (from `docs/thin-spots.md`): a component's claims should not outrun its
evidence. Layers 1–2 put a floor under the guards and core skills; layer 3 is where
this pack goes from "credible" to "measured."
