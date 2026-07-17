# Harness eval lab

The lab checks policy conformance and agent trajectories without turning runtime smoke
runs into a model leaderboard.

## Deterministic floors

```bash
bash evals/guards.test.sh       # original 49 policy cases
bash evals/conformance.test.sh  # native payloads and adapter behavior
bash evals/runner.test.sh       # success/failure/timeout/malformed/unavailable lab cases
```

Secret-shaped fixtures are assembled at runtime. Raw traces, transcripts, diffs, and
scratch repositories live under ignored `evals/results/` and `evals/scratch/`.

## Behavioral runs

Stable command:

```bash
bash evals/run.sh --runtime <claude|codex|opencode|mock> \
  --scenario <tdd-under-deadline|simplify-red-baseline|review-honesty-clean-diff|all> \
  --runs <n>
```

Optional flags include `--model`, `--timeout`, `--results-dir`, `--judge`, and
`--judge-model`. Credentials come only from the installed runtime; the lab never reads
or stores credential configuration.

Each run creates an isolated temporary Git repository, installs a copy of the harness,
passes the scenario prompt to a driver, grades deterministic evidence, and emits a run
JSON plus an aggregate `summary.json`. Run records contain runtime/model, exit and
duration, tool/check counts, changed paths, checks, available token/cost fields, and
artifact locations. Missing usage remains `null` rather than estimated.

The normalized trace interleaves adapter policy events with fixture-generated check
records, so graders can establish check ordering, RED-before-implementation, final
GREEN, path scope, and forbidden actions without trusting the final prose.

`review-honesty-clean-diff` also needs semantic grading. Without `--judge`, a
deterministically clean result is `needs_review`, never `pass`. A requested judge runs
in a fresh session against the rubric and captured evidence; unavailable or malformed
judge output also remains `needs_review`.

The mock driver is deterministic and exists to test the lab. Live results demonstrate
that adapters and scenarios execute on the installed runtimes. They do not establish
general model superiority. Redacted local smoke reports may be committed under
[`evals/reports/`](reports/); raw evidence remains ignored.
