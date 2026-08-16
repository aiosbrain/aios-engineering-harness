# Eval-lab contract

This lab is designed to be consumed by more than one repo. `aios-engineering-harness`
owns the canonical copy; other repos (starting with `aios-workspace`, for onboarding
behavior rather than engineering-loop behavior) vendor the reusable core into their own
`evals/` directory and add their own scenarios on top. This file is the line between
what's safe to sync verbatim and what every consumer must implement itself.

## Core (sync verbatim, no domain assumptions)

These files take no dependency on what a scenario's fixture contains — they only read
the `HARNESS_*` env vars, a scenario's `manifest.json`, and generic driver/grade/judge
record shapes:

- `run.sh` — orchestration loop (setup → install → drive → normalize → grade → judge →
  aggregate). Scenario discovery for `--scenario all` is automatic
  (`scenarios/*/manifest.json`, skipping any directory missing an executable
  `setup.sh`/`grade.sh` or a `prompt.md` so a WIP scenario never gets silently run), so a
  consumer never has to edit this file just to register a new scenario. Also enforces a
  scenario's `forbidden_paths` (fails the run if any changed path matches).
- `judge.sh` in full, including its mock-mode dispatch, `judge.schema.json` — fresh-session
  LLM judge against a scenario's `rubric.md`; defaults to `needs_review`, never a silent
  pass. The mock-mode path is fully domain-agnostic: it looks for an executable
  `mock-judge.sh` inside the scenario's own directory (`$SCENARIO_DIR/mock-judge.sh`,
  receiving the artifact path as `$1`, printing `{"status":...,"reason":...}` on stdout)
  and fails closed if absent. Because that per-scenario logic lives under `scenarios/`
  (never synced — see Adapter points below), re-syncing `judge.sh` verbatim can never
  clobber a consumer's own mock rubrics.
- `lib/exec_timeout.py` — timeout-wrapped subprocess exec with captured stdout/stderr.
- `lib/normalize_transcript.py` — runtime-specific transcript → generic `events.jsonl`.
- `lib/build_observations.py`, `lib/accounting.py` — sanitized lifecycle, attribution,
  Git binding, completeness, and backward-compatible `observations.v1` accounting.
  Accounting keeps total/input/cached-input/cache-creation-input/output/reasoning-output
  dimensions separate. How the prompt dimensions relate is provider-specific, so every
  driver record declares it in `usage.token_model` and accounting never assumes one:
  under `subset_input_v1` (OpenAI/Codex) `input_tokens` is the whole prompt and cached
  input is a subset of it, with no billed cache-creation dimension; under
  `disjoint_input_v1` (Anthropic/Claude) `input_tokens` is the uncached remainder only
  and cache read and cache creation are separate billed dimensions beside it, so the
  three sum to the prompt. Reasoning output is a subset of output under both.
  Pricing prices only the disjoint portions of the declared model, refuses a dimension
  that model does not price, and rejects an unrecognized model outright. Token state is
  complete/partial/unknown against the dimensions the declared model actually models, and
  accounting never derives a missing total — only a driver whose model makes the total
  arithmetically determined (the disjoint sum) may report one it did not receive. Costs are only
  `runtime_reported`, `pricing_estimate`, `allocated_subscription`, or `unknown`.
  Runtime telemetry follows one JSON-safe boundary: each token dimension is a finite,
  nonnegative safe integer no larger than 9007199254740991, and each runtime cost is a
  finite, nonnegative number no larger than that magnitude. Invalid fields become null
  independently, so valid sibling dimensions survive and state is recomputed.
  Runtime-reported values retain source semantics but never assert billed/actual spend;
  estimates and allocations require versioned, ISO-timestamped, recomputable formula
  inputs. Aggregation deduplicates attempts once before hierarchical attempt/phase/issue/
  program rollups, rejects conflicting replays and verified-outcome evidence, and counts
  only verified outcome IDs bound to a passing reviewer/verifier terminal record and its
  exact current SHA. Incomplete telemetry can downgrade a run but never upgrade one.
- `drivers/claude.sh`, `drivers/codex.sh`, `drivers/opencode.sh` — shell out to the real
  runtime CLIs. Verified harness-agnostic: no reference to `.harness/`, `AGENTS.md`, or
  any file `lib/install-harness.sh` creates.

The observation artifact does not change the normalized hook protocol. It is derived
from runtime JSONL, normalized hook traces, harness-owned checks, Git state, driver
results, and phase gates. Raw transcripts remain local ignored artifacts.

## Adapter points (every consumer implements its own)

- **`lib/install-harness.sh`** — same call signature (`$ROOT $WORKSPACE $RUNTIME`)
  everywhere, but its job is repo-specific: this repo's version installs the engineering
  harness's own skills/hooks/adapters into the scratch workspace so a scenario can test
  *this harness* operating on a generic code repo. A consumer whose scenarios exercise a
  different product (e.g. an AIOS personal workspace) writes its own version — often a
  near-no-op, since a scenario's `setup.sh` can build the real fixture directly (e.g. by
  calling that product's own scaffold script) instead of installing anything here.
- **`drivers/mock.sh`** — deterministic, hand-scripted "what a passing (and failing)
  trajectory looks like" per scenario, keyed by `$HARNESS_SCENARIO`. This exists to test
  the lab itself, not the runtimes, so it is inherently scenario-specific and never
  synced — each consumer's mock driver only knows about its own scenarios.
- **`scenarios/`** — the actual atoms (`manifest.json`, `prompt.md`, `setup.sh`,
  `grade.sh`, `mock-judge.sh` when `semantic_required: true` and mock-mode judging is
  needed, and `rubric.md` for the live judge). Fully repo-specific by design; see
  `evals/README.md` for the shape.

## Consuming this lab from another repo

A consumer vendors the **core** list above into its own `evals/` (matching relative
paths so `run.sh` doesn't need patching), writes its own `lib/install-harness.sh` and
`drivers/mock.sh`, and adds its own `scenarios/`. Pin the source commit the core was
vendored from (a version marker file) so drift is visible and re-syncs are deliberate,
never silent — see `aios-workspace/evals/README.md` for the concrete sync mechanism.

Workspace remains explicitly `legacy_unknown` until AIO-754 vendors both accounting
modules after AIO-612. AIO-754 sits under AIO-681 and is blocked by AIO-612 while
blocking AIO-710; until that unsettled final cut lands, do not claim Workspace's current
sync includes detailed accounting. During that staged interval, `run.sh` preserves
legacy execution and emits explicit `legacy_unknown` accounting.
