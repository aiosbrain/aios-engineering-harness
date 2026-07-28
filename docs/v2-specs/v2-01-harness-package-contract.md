---
eval_tier: full
spec_gate: block
safety: false
type: issue-spec
---

# V2-01A — Validate the minimal harness package contract

## What / why

Add one deterministic, versioned contract for the metadata shared by verified
AIOS harness packages. Today the package concept is spread across skills,
rubrics, hooks, commands, fixtures, and product code, so later profile,
installation, runtime-scorecard, and catalog work has no machine-checkable
unit to consume.

This slice establishes only the minimal schema and offline validator. It does
not install, activate, execute, publish, or synchronize a package.

## Outcomes

- A maintainer can validate one harness package manifest offline and receive a
  deterministic pass or a field-specific failure.
- The contract captures identity, compatibility, entry points, data tiers,
  runtime capabilities, verifier metadata, fixtures, and owned paths without
  requiring every future lifecycle field.
- One valid and multiple invalid fixtures demonstrate the contract before a
  profile resolver or installer consumes it.

## Interface / integration points

- `scripts/cli/registry.mjs` — existing CLI registry that will expose the
  validation command.
- `.harness/evals/CONTRACT.md` — existing portable evaluation boundary whose
  evidence concepts the package metadata references without changing its wire
  shape.
- `.harness/hooks/PROTOCOL.md` — existing normalized hook contract; this slice
  records hook references but does not change the protocol.
- `package.json` — existing script and dependency contract. This slice adds no
  dependency.
- New file: `schemas/harness-package.schema.json` — versioned minimal manifest
  schema.
- New file: `scripts/harness-package/validate.mjs` — zero-network validator and
  structured diagnostics.
- New file: `test/harness-package-contract.test.mjs` — positive, negative, and
  path-containment fixtures.
- New directory: `test/fixtures/harness-packages/` — synthetic package
  manifests used only by the test.

Public surface introduced by this slice:

```text
aios harness validate <manifest> [--json]
```

Exit contract:

- `0`: manifest is valid;
- `1`: deterministic contract violation;
- `4`: usage or filesystem error.

JSON output contains `schemaVersion`, `valid`, and a stable `findings` array.
Each finding contains `code`, `path`, and `message`. Exact finding codes are
defined in the new validator and locked by fixtures before later consumers
depend on them.

## Dependencies

Depends on: approval of the v2 fixed decisions.

### Upstream / external context

- `aios-engineering-harness/docs/v2-ecc-workspace-harness-learnings.md` —
  external epic context and fixed decisions; this path is outside the
  `aios-workspace` implementation repository.

If those decisions are not approved, stop before implementation. In
particular, do not infer a package signing scheme, Team Brain wire shape,
runtime equivalence, or automatic activation policy.

## Scope

**In:** one schema version; offline validation; CLI registration; stable exit
contract; valid/invalid fixtures; path-containment checks; contract
documentation; no new dependency.

**Deferred:** package profiles, install state, installation, activation,
execution, migration, signing, remote catalogs, Team Brain exchange, runtime
scorecard generation, telemetry, GUI rendering, and conversion of existing
workflows.

This increment is one PR; follow-ups are deferred to sibling specs. It
introduces one narrow public surface.

## Implementation approach

1. Define the smallest schema and fixture set first.
2. Implement the validator against those fixtures with deterministic finding
   codes and no model or network call.
3. Register the single CLI surface against a mock manifest.
4. Add containment and malformed-input failures.
5. Document the contract and deferred fields after behavior is locked.

The builder may choose the internal validation technique already available in
the repository, but must not add a dependency or silently broaden the schema.

## Acceptance criteria

### Automated

- `node --test test/harness-package-contract.test.mjs` exits `0` and covers one
  valid manifest plus failures for unknown schema version, missing tier,
  unknown runtime capability, undeclared owned path, and a path escaping the
  package root.
- `node scripts/aios.mjs harness validate
  test/fixtures/harness-packages/valid/manifest.json --json` exits `0`; stdout
  parses as JSON with `valid: true` and an empty `findings` array.
- The same command against
  `test/fixtures/harness-packages/path-escape/manifest.json --json` exits `1`;
  stdout contains `valid: false` and the fixture-locked containment finding
  code.
- `npm test` exits `0`.
- `npm run lint` exits `0`.
- `npm run format:check` exits `0`.
- `git diff --check` exits `0`.
- `git diff -- package.json` shows no added production dependency.
- `git diff -- .harness/hooks/PROTOCOL.md .harness/evals/CONTRACT.md` is empty.

### Manual

- Run `aios harness validate` with no path and confirm it exits `4`, prints
  usage, and creates no file.
- Review the schema and confirm every path named by the manifest is either
  package-relative or explicitly identified as an existing external contract.

## Rollback and failure behavior

- Removing the new CLI registry entry, validator, schema, fixtures, and tests
  fully rolls back this slice because no persistent state or migration is
  introduced.
- Unknown schema versions, tiers, capabilities, and fields that affect writes
  fail closed; the validator never repairs or rewrites a manifest.
- Read or parse failure produces exit `4` and no partial output file.

## Build-with

Build-with: frontier coding model, high effort.

Recommended builder skill: `ai-code-review` after implementation because the
new manifest governs executable package references and path containment. No
second builder skill is required.

## Tier safety

No Brain or sync surface is added. Package manifests may declare
`admin`, `team`, or `external` data tiers, but this slice only validates those
literal declarations. It does not move data across tiers.

Missing or unknown tier declarations fail closed. No raw evaluation evidence,
memory, telemetry, credentials, or user content is written or synchronized.
