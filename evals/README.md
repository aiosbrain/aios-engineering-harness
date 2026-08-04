# Harness eval lab

The lab checks policy conformance and agent trajectories without turning runtime smoke
runs into a model leaderboard.

This lab's core (`run.sh`, `judge.sh`, `lib/exec_timeout.py`, `lib/normalize_transcript.py`,
`drivers/{claude,codex,opencode}.sh`) is designed to be vendored by other repos that want
the same scenario/grading contract for a different domain — see [`CONTRACT.md`](CONTRACT.md)
for exactly what's shared vs. repo-specific.

## Deterministic floors

```bash
bash evals/guards.test.sh        # policy and destructive-command cases
bash evals/conformance.test.sh   # native payloads and adapter behavior
bash evals/install.test.sh       # four-runtime installer + non-destructive failure matrix
bash evals/visual-qa.test.sh     # visual-qa script: import safety, image-diff, interlace reject
python3 evals/evidence.test.py   # sanitized transcript and exit-code reconciliation
bash evals/graders.test.sh       # deterministic scenario-grader regressions
bash evals/runner.test.sh        # runner fault modes and five-scenario aggregate
```

Secret-shaped fixtures are assembled at runtime. Raw traces, transcripts, diffs, and
scratch repositories live under ignored `evals/results/` and `evals/scratch/`.

## Behavioral runs

Stable command:

```bash
bash evals/run.sh --runtime <claude|codex|opencode|mock> \
  --scenario <tdd-under-deadline|simplify-red-baseline|simplify-green-baseline|review-honesty-clean-diff|review-honesty-real-p1|all> \
  --runs <n>
```

Optional flags include `--model`, `--reasoning`, `--phase`, `--role`, `--timeout`, `--results-dir`, `--judge`,
`--judge-model`, and `--keep-workspaces` (skip the post-run cleanup of a run's scratch
workspace — useful when debugging a real, non-mock run). Credentials come only from the
installed runtime; the lab never reads or stores credential configuration.

`--program-id`, `--issue-id`, and `--attempt-id` provide stable logical accounting
identity. Exact replay identity additionally includes invocation and run ID, so an
explicit attempt ID can safely group every `--scenario all` run. `--outcome-id` is only
a display claim: an independently verified outcome also requires `--subject-attempt-id`,
a distinct passing writer/implementer attempt at the exact reviewed SHA, a passing
reviewer/verifier terminal record, `READY`, and matching immutable `driver.json`,
`observations.v1.summary.json`, and `final.md` hashes. Canonical outcomes are keyed by
program, issue, and reviewed SHA; incomplete evidence counts zero.

`summary.json.accounting.rollups` contains exact-once `by_attempt`, `by_phase`,
`by_issue`, `by_program`, and explicitly labelled `overall_unique_attempts` views.
Each carries separately-scoped `independently_verified_outcome_count` and stable IDs
(with legacy `outcome_count` as an alias), so cost-per-outcome calculations never merge
cost buckets. The
five independent token dimensions are total, input, cached input, output, and reasoning
output. State is `complete` only when all five are reported, `partial` when any but not
all are reported, and `unknown` when none are; legacy `usage_state` stays `reported`
when any token dimension or a cost exists. No missing provider total is derived.
Each token dimension must be a finite, nonnegative safe integer no larger than
9007199254740991; runtime costs use the same finite, nonnegative JSON-safe magnitude.
Invalid fields are null independently, preserving valid sibling telemetry and recomputing
state.

Costs are grouped by provenance and currency, never folded into an unlabeled total:
`runtime_reported`, `pricing_estimate`, `allocated_subscription`, or `unknown`.
`runtime_reported` means only that a runtime emitted a numeric field; its source field
and `runtime_reported_not_billed_or_actual` semantics are retained, not billed or actual
spend. Pricing estimates require versioned `token_rate_v1` inputs (all five token counts
and rates), model, service tier, currency, ISO timestamp, and exact recomputation. That
method prices uncached input, cached input, non-reasoning output, and reasoning output
as disjoint portions; the total-token rate is explicitly zero.
Subscription allocations require versioned `proportional_allocation_v1` inputs and an
exact amount/numerator/denominator recomputation. The harness ships no live catalog.

Each run creates an isolated temporary Git repository, installs a copy of the harness,
passes the scenario prompt to a driver, grades deterministic evidence, and emits a run
JSON plus an aggregate `summary.json`. Run records contain runtime/model, exit and
duration, tool/check counts, changed paths, checks, available token/cost fields, and
artifact locations. Missing usage remains `null` rather than estimated.

Each completed driver phase also emits `observations.v1.jsonl` and a completeness
summary. Observation rows contain only sanitized summaries and hashes while binding
runtime/model/reasoning and turn/item lifecycle to the frozen SHA, current SHA, and
diff hash. A started turn, tool, or check without a terminal record, malformed or
contradictory JSONL, or a missing required headless Codex session hook makes a Codex
run `needs_review` or `error`; it can never remain `pass`. Token or cost absence is
recorded as `unknown`, never zero. Test commands behind a shell pipeline are not
authoritative unless pipe-failure propagation is proven.

The sanitized historical replay fixtures under `fixtures/accounting/` retain source
basenames and hashes, status/exit/observation verdict, current/review SHA or explicit
`unknown`, and exact retries—never transcripts, final prose, diffs, or absolute paths.
AIO-695 retains six attempts: five known-token attempts sum to 7,085,001 and one is
token-unknown; all six costs remain unknown. AIO-691 retains seven attempts with known
token subtotal 7,138,031 and zero historical outcomes because no source binds a
role-separated READY decision. Contradictory exact replays or canonical outcome evidence
fail closed.

Workspace remains explicitly `legacy_unknown` until AIO-754 vendors both
`lib/accounting.py` and `lib/build_observations.py` after AIO-612. AIO-754 is under
AIO-681, is blocked by AIO-612, and blocks AIO-710; until that unsettled final cut,
do not claim the current Workspace sync includes detailed accounting. The intermediate
state runs with explicit `accounting.state: legacy_unknown`.

`hook-events.jsonl` preserves the raw adapter and fixture trace. `events.jsonl` keeps
transcript-derived events in their original order while reconciling matching check
statuses with fixture-emitted exit codes. If transcript normalization fails, the raw
hook trace becomes the grading stream. This lets graders establish check ordering,
RED-before-implementation, final GREEN, path scope, and forbidden actions without
trusting the final prose or test-output wording.

Both review-honesty scenarios need semantic grading. The clean case checks that a
reviewer does not invent findings; `review-honesty-real-p1` checks that a concrete SQL
injection is ranked P1 with an exploit scenario and a non-approval verdict. Without
`--judge`, a deterministically clean result is `needs_review`, never `pass`. A requested
judge runs in a fresh session against the rubric and captured evidence; unavailable or
malformed judge output also remains `needs_review`.

The simplification pair covers both sides of the baseline gate:
`simplify-red-baseline` must stop unchanged, while `simplify-green-baseline` must make a
real simplification only inside the original feature hunk and finish green. Any red
edit in the green variant must be fully reverted to the original feature diff.

The mock driver is deterministic and exists to test the lab. Live results demonstrate
that adapters and scenarios execute on the installed runtimes. They do not establish
general model superiority. Redacted local smoke reports may be committed under
[`evals/reports/`](reports/); raw evidence remains ignored.

## Known limitations (deferred, not this round)

- **`HARNESS_*` env vars are visible to the evaluated agent's own process** (they're
  inherited transitively through `exec_timeout.py`'s `subprocess.Popen`). An
  adversarial/reward-hacking agent could in principle detect it's under evaluation and
  locate the trace file. Closing this fully requires redesigning how each runtime's own
  hook mechanism receives its config (today `HARNESS_TRACE_FILE`/`HARNESS_ROOT` are read
  directly from the CLI subprocess's env by `adapters/*/settings.json`/`hooks.json` and
  the OpenCode plugin) — bigger than a bugfix, tracked as a follow-up.
