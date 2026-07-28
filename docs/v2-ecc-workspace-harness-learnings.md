# AIOS v2.0 — ECC and workspace harness learnings

Status: proposed epic brief

Prepared: 2026-07-28

Decision owner: AIOS product and engineering

Intended use: source document for a Linear v2.0 epic and its child issues

## Spec-workflow status

This document is an **epic context document**, not a builder-ready issue spec.
Under the AIOS `author-ready-spec` and `evaluate-spec-readiness` contract, a
builder-facing spec must be a single reviewable increment. The epic therefore
must not be handed directly to an implementation agent.

The Linear hierarchy should be:

```text
v2.0 epic (this document: context, decisions, outcomes, sequencing)
  └─ workstream (coordination container)
       └─ issue spec (one reviewable PR, evaluated by `aios spec eval`)
```

The first cold-start buildable issue is maintained alongside this document as
[`v2-01-harness-package-contract.md`](v2-specs/v2-01-harness-package-contract.md).
It is the contract stub at the start of the default vertical slice. Remaining
issue specs should be authored only after their dependencies and unresolved
product decisions are closed.

## Executive decision

AIOS should not copy ECC or expand into a large prompt catalog. It should combine
three assets that are already complementary:

1. **The engineering harness** supplies the portable enforcement substrate:
   normalized hook protocol, runtime adapters, conformance tests, deterministic
   guards, and an executable eval lab.
2. **`aios-workspace`** supplies the actual product system: verified operator
   loops, privacy tiers, Team Brain boundaries, safe toolkit upgrades,
   worktree-first shipping, review gates, durable journals, and user-facing CLI
   and GUI surfaces.
3. **ECC** demonstrates a useful product control plane: selectable component
   profiles, machine-readable installation plans, managed install state,
   doctor/repair/uninstall, stable hook identities, adapter capability
   scorecards, and explicit memory/handoff primitives.

The v2.0 opportunity is therefore:

> Make verified AIOS workflows installable, inspectable, portable, measurable,
> and recoverable across supported runtimes, while preserving local-first
> privacy and human approval.

This is a control-plane and productization release, not a catalog-volume
release. The atomic product unit should be a **verified harness package**, not a
skill, prompt, hook, or agent in isolation.

## Evidence baseline

This analysis is pinned to:

| System | Revision | Evidence reviewed |
|---|---|---|
| `aios-engineering-harness` | `37b1a46a4fa697a1dbb405a616f37187e40d09e9` | Protocol, adapters, hook policies, eval contract, scenarios, conformance tests, runtime docs |
| `aios-workspace` | `cd7bb3fb734ff42baf45e1eeab67a0589a6b5d96` | Product roadmap, v1 release status, operator-loop specs and implementation, update/merge machinery, maturity loop, runtime adapters, CLI registry, tests, vendored `.harness` |
| ECC | [`4e973d3`](https://github.com/affaan-m/ECC/commit/4e973d3eaf92d97f8d2e2d8abb39d8bdc8711b38) | README, install profiles, installer and CLI lifecycle, hooks, runtime mappings, adapter scorecard, continuous learning, unified memory, contract-first and eval skills |

ECC is a fast-moving external project. Revalidate its behavior before using
implementation details, dependencies, or license-sensitive content. The
recommendations below concern product patterns and contracts, not source-code
copying.

## Three-way comparison

| Dimension | Engineering harness | Actual `aios-workspace` | ECC | v2.0 implication |
|---|---|---|---|---|
| Primary role | Portable policy and verification substrate | Local-first operator product and toolkit | Broad agent configuration distribution | Keep the layers distinct; add a control plane above them |
| Runtime model | First-class Claude Code, Codex, Cursor, and OpenCode adapters around one normalized protocol | Product runtime adapters plus vendored engineering harness; some workspace hooks remain runtime-shaped | Claude-native core with mappings or partial equivalents elsewhere | Use the engineering protocol as the policy seam; publish explicit capability parity |
| Workflow quality | Executable scenarios, judges, evidence schema, and conformance | Strong unit/integration/product tests; only a small number of workspace-specific behavioral scenarios | Guidance-heavy eval skill and many reusable patterns | Convert the best workspace workflows into fixture-backed harness packages |
| Distribution | Drop-in curated pack; intentionally small | Scaffold/update flow with managed files, create-only seeds, provenance, three-way merges, and conflict sidecars | Profiles, plans, install state, doctor, repair, uninstall | Extend AIOS update safety into a complete package lifecycle |
| Catalog | Curated skills, agents, guards, and rubrics | Generated skill/integration catalogs; 17 scaffold skills plus local engineering skills | Very large catalog: hundreds of skills and dozens of agents/commands | Optimize for verified coverage and trust, not item count |
| Memory and learning | Context injection and continuation primitives; policy focused | Admin-local maturity observations, instincts, session briefs, evidence ledger, daily/weekly synthesis | Unified memory and continuous-learning workflows | Productize the existing AIOS maturity loop with consent, provenance, expiry, and evaluation |
| Governance | Deterministic guards and conformance contracts | Access tiers, default-deny sync, human approval, exact-head review, worktree enforcement, Team Brain boundary | Install selection and hook profiles; weaker product data boundary | AIOS governance remains authoritative |
| Operations | Zero-dependency shell/Python core; Bun only for OpenCode tests | Node 22 product with CLI, GUI, SQLite, journals, supervisors, and recovery logic | Node-based installer/control CLI | Put rich lifecycle UX in workspace; keep the portable core zero-dependency |
| Product telemetry | Eval evidence and judge outcomes | Operator-loop telemetry, verifier states, review results, correction paths | Adapter compliance and optional learning signals | Define privacy-preserving quality/cost telemetry per harness |

## What AIOS already does better

These are foundations to preserve, not rewrite.

### Safe customization and upgrades

The workspace update system already distinguishes managed files from
create-only seeds, performs three-way merges, detects dirty paths and conflict
markers, handles upstream deletions, emits conflict sidecars, and supports a
contribution path. This is materially safer than a simple copy-based installer.

ECC's lifecycle commands are still useful, but they should become a thin
control plane over AIOS's existing ownership and merge semantics.

### Verified operational workflows

AIOS has real workflow state machines rather than a collection of prompts:

- the verified daily and weekly operator loops;
- a durable evidence ledger with verifier/correction stages;
- decision, ask, and transcript extraction pipelines;
- `aios ship` with worktree isolation, spec and plan gates, exact-head review,
  security review, bounded waits, and merge controls;
- the unified inbox's append-only journal, deterministic SQLite projection,
  outbox, audit chain, retention, redaction, and capability controls.

ECC offers useful patterns, but AIOS has the stronger basis for trusted
execution.

### Privacy and authority boundaries

AIOS's admin/team/external tiers, default-deny synchronization, and pinned
Team Brain API contract are product-level controls. The unified inbox further
separates coordinator, owning runtime, and policy-gateway authority. The
maturity loop is explicitly admin-tier and local-only.

No v2.0 feature should weaken these boundaries for convenience or telemetry.

### Regression depth

The workspace has broad deterministic tests, build checks, redaction tests,
coverage controls, and mutation testing. The engineering harness adds
cross-runtime conformance and behavioral judging. This combination is more
valuable than ECC's catalog breadth.

## What to learn from ECC

### 1. Treat installation as a managed lifecycle

ECC exposes planning, application, recorded state, diagnosis, repair, and
uninstall as one lifecycle. AIOS has excellent update mechanics but does not
yet present one coherent ownership contract for every installed harness
component.

Adopt:

- deterministic `plan` output before mutation;
- human-readable and JSON output modes;
- a versioned install-state ledger;
- `doctor` that distinguishes missing, modified, incompatible, and orphaned
  components;
- `repair` that reuses the normal merge engine;
- scoped uninstall based on recorded ownership;
- component provenance and last-known content hashes.

Do not replace AIOS's three-way merge or create-only seed rules.

### 2. Make profiles declarative and inspectable

ECC's install profiles turn a large set of components into named,
machine-readable selections. AIOS should use the same pattern at a smaller,
more intentional scale.

Profiles should express user outcomes such as `solo-operator`,
`team-operator`, `harness-author`, and `full`, not arbitrary technology stacks.
They must resolve to a deterministic plan and may only select validated
packages compatible with the current workspace and runtime.

### 3. Give hooks stable identities and explicit profiles

Stable hook IDs make installation, diagnostics, compatibility, overrides, and
telemetry understandable. AIOS currently has strong hook behavior but multiple
surfaces: the vendored normalized harness, root product hooks, and runtime
configuration.

Add a registry that records:

- stable ID and version;
- event and normalized input contract;
- mode: block, advise, capture, or enrich;
- supported runtimes and degradation behavior;
- tier/data classification;
- timeout and failure policy;
- owning package and tests.

Changing the normalized wire protocol remains a separate RFC requiring adapter
and consumer coordination.

### 4. Publish runtime parity as evidence, not marketing

ECC's adapter scorecard is a good product pattern even where its runtimes are
not truly equivalent. AIOS can make this stronger by generating the scorecard
from conformance fixtures.

Each package should declare capabilities as:

- native;
- adapted and conformant;
- instruction-backed;
- degraded with a documented reason;
- unsupported.

The published matrix must link to the test or fixture that proves the claim.

### 5. Productize memory as governed evidence

ECC makes memory, handoffs, and continuous learning explicit user concepts.
AIOS already has safer primitives: evidence records, session briefs,
observations, instincts, maturity scoring, and local-only storage.

The lesson is to expose and govern those primitives, not to add another
unbounded memory store. Every learned item needs source provenance, tier,
confidence, creation time, last validation, expiry/review policy, and a way to
inspect, reject, or forget it. Automatic observation must remain opt-in and
must not sync by default.

### 6. Validate catalog hygiene continuously

ECC's size makes catalog drift visible: duplicates, aliases, stale references,
runtime-specific gaps, and unclear ownership become inevitable. AIOS should
prevent those problems before growing its catalog.

Validate unique IDs, package shape, references, runtime claims, tier policy,
fixtures, provenance, deprecation aliases, and generated catalog freshness in
CI.

### 7. Make context budgets a package concern

ECC highlights compaction and context-management patterns. AIOS should make
context cost visible at harness-package level: source budget, prompt/runtime
overhead, expected tool calls, compaction checkpoints, and quality/cost
telemetry. This belongs in package metadata and evaluations, not as a universal
prompt trick.

## What not to import

- Do not chase ECC's catalog size. Five trusted harnesses are better than
  hundreds of unverified prompts.
- Do not make Claude Code's native payload the shared hook contract.
- Do not duplicate policy logic per runtime.
- Do not add Node dependencies to the engineering harness's zero-dependency
  shell/Python surface.
- Do not auto-enable transcript observation or learned behavior.
- Do not allow a pulled skill or harness to auto-activate.
- Do not create a marketplace before package validation, provenance,
  compatibility, and uninstall are reliable.
- Do not treat agent count, parallelism, or command count as product quality.
- Do not send admin-local evidence or maturity data across the Team Brain
  boundary without an explicit, versioned protocol decision.

## Proposed v2.0 epic

### Title

**AIOS v2.0 — Verified Harness Control Plane**

### Problem

AIOS's strongest workflows are implemented across product code, skills, hooks,
rubrics, tests, and the vendored engineering harness. They are trustworthy in
the repository but are not yet one inspectable product unit that users can
plan, install, diagnose, evaluate, compare, upgrade, or remove consistently
across runtimes.

The v1 backlog also contains user-facing inbox and runtime work. Shipping those
features without the package, capability, and lifecycle contracts would add
more surfaces that are hard to reason about and support.

### Goal

Deliver a v2.0 control plane in which a user can:

1. choose an outcome-oriented profile;
2. preview the exact changes and compatibility;
3. install verified harness packages safely;
4. run them through CLI and supported GUI/runtime surfaces;
5. inspect verifier, cost, provenance, and learned-context evidence;
6. diagnose, repair, upgrade, or uninstall them without losing user edits.

### Fixed decisions

- The engineering harness remains the portable policy and conformance layer.
- `aios-workspace` remains the product control plane and owns rich Node/SQLite
  lifecycle behavior.
- The normalized hook protocol is not changed implicitly by this epic.
- Existing three-way merge, create-only seed, sidecar, worktree, tier, and
  human-approval guarantees are preserved.
- Pulled packages never auto-activate.
- Learning and telemetry are local-only and opt-in unless a later,
  version-first Team Brain contract explicitly permits a bounded export.
- Runtime capability claims describe proven behavior, including degradation;
  they do not promise artificial parity.

### Existing integration baseline

These are existing `aios-workspace` paths against which issue specs should be
evaluated:

- `scripts/update.mjs` — toolkit update orchestration;
- `scripts/update/merge.mjs` — managed-file, seed, deletion, and sidecar
  behavior;
- `scripts/update/manifest-walk.mjs` — safe manifest traversal and drift
  inventory;
- `scripts/cli/registry.mjs` — CLI command registry;
- `hooks/instinct-observe.mjs` and `scripts/analyze/maturity-store.mjs` —
  maturity observation state;
- `gui/server/runtime-adapters/` — product runtime adapters;
- `src/operator-loop/inbox/` — inbox journal and domain logic;
- `.harness/hooks/PROTOCOL.md` and `.harness/evals/CONTRACT.md` — vendored
  portable protocol and evaluation contracts;
- `test/toolkit-update.test.mjs` — update regression surface.

Paths proposed by a child issue must be marked as new until they exist.

### Epic build-with and tier posture

Build-with: frontier coding model, high effort for contract and migration
slices; standard coding model, medium effort for bounded catalog/documentation
slices. Each child issue should narrow this further.

Tier safety: admin-local is the default for install state, raw evaluation
evidence, maturity data, and telemetry. Team Brain receives only explicitly
approved, schema-bounded team-tier artifacts through a versioned contract.
Unknown tier, capability, ownership, or compatibility values fail closed.

### Success metrics

- Five production harnesses conform to one versioned package contract.
- All advertised runtime capabilities are backed by conformance evidence.
- A clean profile install, upgrade, repair, and uninstall pass end-to-end
  fixtures without modifying unowned files.
- Locally modified managed files survive upgrades or produce explicit
  sidecars; no silent overwrite is accepted.
- Every production harness includes representative fixtures, a rubric,
  verifier status, and a sample run.
- CLI, cockpit, and Team Brain artifacts expose the same verifier state
  vocabulary.
- Quality, correction-loop, latency, and cost telemetry can be collected
  locally without crossing the declared tier boundary.
- A user can inspect and delete learned items; no learning or sync is enabled
  without explicit consent.

## Workstreams and Linear issue families

The V2 identifiers below are coordination families, not yet builder-ready
issues. Do not paste a whole family into `aios ship`. Author and evaluate the
single-PR slices in the issue map that follows.

### V2-00 — Freeze the v2 architecture and release contract

**Outcome:** one approved contract defining package boundaries, ownership, data
tiers, runtime capability vocabulary, compatibility, and v2 migration rules.

**Acceptance:**

- Records the boundary between workspace product code and the portable
  engineering harness.
- Decides whether root product hooks wrap the normalized protocol, remain
  product-only adapters, or require a future protocol extension.
- Defines the stable verifier-state vocabulary used by CLI, GUI, and Team
  Brain.
- Includes threat model, rollback model, and cross-repository ownership.
- Any protocol-wire change is isolated into an explicitly approved RFC.

**Depends on:** none.

### V2-01 — Define the verified harness package contract

**Outcome:** a versioned manifest and validator for the atomic product unit.

Minimum fields:

- stable ID, version, owner, provenance, license, and compatibility;
- job-to-be-done and supported entry points;
- sources, outputs, schemas, tiers, and write authorities;
- workflow stages and verifier rubric;
- hooks, skills, agents, commands, and runtime capabilities;
- fixtures, sample run, expected quality, latency, and cost envelope;
- dependencies, conflicts, migrations, and deprecation aliases.

**Acceptance:**

- JSON Schema or an equivalently deterministic schema is versioned.
- Validator has positive and negative fixtures.
- Manifest references cannot escape the package.
- Unknown capabilities and undeclared writes fail validation.
- The contract supports a simple single-pass harness without forcing every
  possible stage.

**Depends on:** V2-00.

### V2-02 — Build profiles and deterministic planning

**Outcome:** named profiles resolve to an exact, reviewable package/component
plan.

**Acceptance:**

- Ships `solo-operator`, `team-operator`, `harness-author`, and `full` only if
  each represents a proven user need.
- `aios harness plan <profile>` supports human and JSON output.
- Plan shows add/change/remove/no-op, ownership, runtime degradation, tier,
  and dependency reasons.
- Repeated planning against unchanged state is byte-stable apart from
  documented timestamps.
- Planning performs no filesystem or remote mutation.

**Depends on:** V2-01.

### V2-03 — Add install state, doctor, repair, and scoped uninstall

**Outcome:** complete lifecycle management built on the existing safe update
engine.

**Acceptance:**

- Install state records package versions, owned paths, hashes, provenance,
  profile selection, and migrations.
- `doctor --json` distinguishes drift, missing files, incompatibility,
  unresolved sidecars, stale aliases, and orphaned ownership.
- `repair` uses three-way merge and create-only seed semantics.
- Uninstall removes only unchanged owned material; modified paths are retained
  or explicitly sidecarred.
- Interrupted operations are recoverable and idempotent.
- Existing `aios update --check` and `--contribute` behavior remains intact.

**Depends on:** V2-01, V2-02.

### V2-04 — Create hook registry and evidence-backed runtime scorecard

**Outcome:** one inspectable registry for portable guards and product hooks,
with generated runtime parity.

**Acceptance:**

- Each hook has stable ID, version, mode, event, timeout, failure policy,
  owner, and tier classification.
- Runtime claims use the native/adapted/instruction-backed/degraded/
  unsupported vocabulary.
- Claims are generated from conformance results where executable support
  exists.
- Product runtime adapters and policy adapters are clearly distinguished.
- No native runtime payload parsing is added to portable `hooks/*.sh`.

**Depends on:** V2-00, V2-01.

### V2-05 — Convert five workflows into reference harness packages

**Outcome:** the package contract is proven against real, varied workflows.

Recommended reference set:

1. verified weekly synthesis;
2. decision audit;
3. scope-creep review;
4. transcript decisions;
5. stakeholder/workstream update.

**Acceptance:**

- Each package passes validation and includes fixtures, rubric, verifier,
  correction behavior, sample output, and tier policy.
- At least one package proves writeback with human approval.
- At least one package proves single-pass is preferable to a correction loop.
- Existing commands remain compatible through explicit aliases or migrations.
- Package installation does not auto-activate pulled code.

**Depends on:** V2-01 through V2-04.

### V2-06 — Expand behavioral evals and package telemetry

**Outcome:** workspace product workflows gain the behavioral evidence already
expected by the engineering harness.

**Acceptance:**

- Adds scenarios for package install/upgrade conflict, verifier correction,
  tier denial, runtime degradation, and safe uninstall.
- Adds gold fixtures for the five reference packages.
- Compares package versions on quality, corrections, latency, and cost.
- False positives and human rejection reasons use a stable local schema.
- CI separates deterministic gates from optional live-model evaluation.
- Telemetry is local by default and its export contract is tier-gated.

**Depends on:** V2-01, V2-04, V2-05.

### V2-07 — Govern and productize the maturity/memory loop

**Outcome:** existing observations, instincts, and session context become an
inspectable, consent-based subsystem.

**Acceptance:**

- Learned records include provenance, confidence, tier, timestamps, review
  state, and expiry.
- Users can list, inspect, approve, reject, edit, export, and forget records.
- Observation is opt-in and visibly enabled.
- Retrieval has deterministic limits and records which memories influenced a
  run.
- Scoring abstains below corpus thresholds and is regression-tested.
- Nothing syncs to Team Brain without a separate versioned contract and
  explicit approval.

**Depends on:** V2-00, V2-06.

### V2-08 — Complete the v2 inbox and runtime product surface

**Outcome:** the deferred v2 inbox/GUI work consumes the shared package,
capability, verifier, and policy contracts.

Candidate existing backlog: AIO-452, AIO-454–462, AIO-394, AIO-464,
AIO-465, AIO-441–443, and AIO-467. Re-triage before attaching them; do not
blindly reopen all items.

**Acceptance:**

- GUI operations map to the append-only inbox journal and existing authority
  model.
- CLI and GUI show package version, runtime capability, verifier status, and
  pending approvals consistently.
- Reply/archive/thread behavior remains crash-safe and replayable.
- External ingestion declares tier, retention, redaction, and credential
  boundaries.
- Codex and OpenCode runtime behavior advertises only tested capabilities.

**Depends on:** V2-01, V2-04; can proceed in parallel with V2-05 through V2-07
once the contracts are stable.

### V2-09 — Team Brain aggregation and harness exchange

**Outcome:** verified artifacts and packages can cross the team boundary under
the pinned API contract.

**Acceptance:**

- Aggregation consumes stable, tier-approved artifacts rather than local raw
  observations.
- Share/pull/install preserves provenance and never auto-activates code.
- Compatibility and signature/integrity failures are visible before install.
- Conflicts and drift can be pulled back to individuals without overwriting
  local state.
- Any wire-shape change lands version-first in the Brain contract and matching
  implementation.

**Depends on:** V2-01, V2-03, V2-05, V2-06 and explicit Team Brain
coordination.

### V2-10 — Migration, release hardening, and documentation

**Outcome:** existing v1 users can adopt v2 without losing customizations,
history, or trust.

**Acceptance:**

- Migration inventories current scaffold, local customizations, installed
  skills, maturity data, and unresolved sidecars.
- Migration is dry-runnable, resumable, idempotent, and rollback-tested.
- v1 commands either remain supported or return actionable migration guidance.
- Clean install, v1 upgrade, customized upgrade, offline diagnosis, repair,
  and uninstall are covered in release fixtures.
- Catalog, docs, schemas, examples, and scorecards are drift-checked in CI.
- Full workspace and engineering-harness verification suites are green.

**Depends on:** all shipping workstreams.

## Linear issue-slicing map

Create workstream containers first, then author each row below as its own
candidate spec using `author-ready-spec`. Run `aios spec eval` before a builder
or `aios ship` receives it. A row may be split further when repository
inspection shows it cannot remain one reviewable PR; rows must not be combined
merely to reduce issue count.

| Proposed slice | One-PR outcome | Depends on |
|---|---|---|
| V2-00A | Architecture ADR fixes product/core boundaries, ownership, tiers, and verifier vocabulary | None |
| V2-00B | Protocol decision records which product hooks can use the existing normalized wire shape | V2-00A |
| V2-01A | Minimal package schema, offline validator, fixtures, and one CLI surface | V2-00A |
| V2-01B | Compatibility and dependency validation extends the proven minimal schema | V2-01A |
| V2-02A | Profile schema and deterministic resolver produce an internal component plan | V2-01B |
| V2-02B | Human and JSON plan renderers expose add/change/remove/no-op and degradation reasons | V2-02A |
| V2-03A | Versioned install-state ledger records ownership, hashes, and provenance | V2-02B |
| V2-03B | Read-only doctor reports drift, missing paths, sidecars, incompatibility, and orphans | V2-03A |
| V2-03C | Repair reuses three-way merge and seed semantics for one failure class | V2-03B |
| V2-03D | Scoped uninstall preserves modified or unowned paths | V2-03A, V2-03B |
| V2-04A | Stable hook registry covers portable and product-only hooks without protocol changes | V2-00B, V2-01A |
| V2-04B | Conformance results generate the runtime capability scorecard | V2-04A |
| V2-05A | Weekly synthesis becomes the first reference package | V2-01B, V2-04A |
| V2-05B | Decision audit becomes a reference package | V2-05A |
| V2-05C | Scope-creep review becomes a reference package | V2-05A |
| V2-05D | Transcript decisions becomes a reference package | V2-05A |
| V2-05E | Workstream update becomes a reference package | V2-05A |
| V2-06A | Behavioral scenarios cover package validation, tier denial, and runtime degradation | V2-04B, V2-05A |
| V2-06B | Lifecycle scenarios cover customized upgrade, repair, and safe uninstall | V2-03D |
| V2-06C | Local telemetry schema records verifier, correction, latency, cost, and rejection outcomes | V2-05A, V2-06A |
| V2-07A | Learned-record schema adds provenance, consent, confidence, review, and expiry | V2-00A |
| V2-07B | Inspect/reject/forget CLI operates only on admin-local learned records | V2-07A |
| V2-07C | Bounded retrieval emits an influence trace and abstains below evidence thresholds | V2-07B, V2-06C |
| V2-08A | Cockpit reads package, capability, verifier, and approval state through existing domain APIs | V2-01B, V2-04B |
| V2-08B+ | Re-triaged inbox GUI and ingestion slices, one authority-preserving behavior per PR | V2-08A |
| V2-09A | Team-tier verified artifact envelope is added version-first to the Brain contract | V2-00A, V2-06C |
| V2-09B | Share/pull preserves package integrity, provenance, compatibility, and inactive-by-default state | V2-03A, V2-09A |
| V2-10A | Dry-run v1 inventory and migration plan cover customizations, state, and sidecars | V2-03B |
| V2-10B | Resumable migration implements the approved inventory plan with rollback fixtures | V2-10A |
| V2-10C | Release matrix proves clean install, customized upgrade, offline doctor, repair, and uninstall | All release-blocking slices |

This map is deliberately interface-first: contract and deterministic consumer
stubs precede lifecycle logic, packages, GUI, and external exchange.

## Applied AIOS spec evaluation

The first executable slice,
[`V2-01A`](v2-specs/v2-01-harness-package-contract.md), was authored using the
AIOS `author-ready-spec` contract and evaluated with the normal
`evaluate-spec-readiness` workflow.

| Evidence | Value |
|---|---|
| Verdict | `SPEC_READY` |
| Exit code | `0` |
| Score | `95` |
| Candidate SHA-256 | `981831fb4bc38513e58966bc9213265ad200299bafcefae00566bcb2aefc184e` |
| Evaluated repository | `aios-workspace` |
| Repository SHA | `914765c472664e907111df5459abd7d266e50c8b` |
| Repository state | clean |
| Evaluation tier | full deterministic + adversarial |

The remaining findings are non-blocking:

- new schema, validator, and fixture paths do not resolve yet because the spec
  explicitly creates them;
- the external epic-context path is outside the evaluated workspace;
- SR12 recommends adding the eventual Linear epic identifier after creation;
- SR13 recommends an even more explicit zero-LLM capture step before
  model-assisted implementation.

No repair pass was required because no must-fail finding remained. Publishing
was not attempted; `linear-publish-spec` requires a separate explicit request,
a publishable evaluation on the final candidate, a clean tree, and
exclusive-editor confirmation.

## Recommended sequence

```text
V2-00 architecture contract
  └─ V2-01 package contract
       ├─ V2-02 profiles and plan
       │    └─ V2-03 lifecycle
       ├─ V2-04 hook registry and runtime parity
       └─ V2-05 five reference packages
            └─ V2-06 evals and telemetry
                 └─ V2-07 governed learning

V2-01 + V2-04 ── V2-08 inbox/runtime surface
V2-03 + V2-05 + V2-06 ── V2-09 Team Brain exchange
all shipping streams ── V2-10 migration and release
```

The contracts should be proven by migrating real workflows early. Avoid
building a generic SDK in isolation and discovering later that the weekly
loop, inbox, or tier rules do not fit it.

## Epic-level non-goals

- A public marketplace or monetization system.
- Hundreds of new skills, commands, or agents.
- Replacing Team Brain or changing its protocol implicitly.
- Cross-device synchronization of raw admin-local memory.
- Unattended external writeback.
- Perfect behavioral equivalence where a runtime lacks the required primitive.
- Rewriting the unified inbox journal or workspace update merge engine.
- Moving product-only Node/SQLite concerns into the portable engineering
  harness.

## Risks and controls

| Risk | Control |
|---|---|
| Package contract becomes an abstract framework | Prove it against five existing workflows before freezing v1 |
| Lifecycle layer silently overwrites customization | Reuse three-way merge, sidecars, ownership hashes, and destructive-operation fixtures |
| Runtime parity is overstated | Generate claims from conformance evidence and label degradation explicitly |
| Catalog becomes a prompt dump | Require fixtures, rubric, verifier, provenance, tiers, and compatibility before listing |
| Learning becomes opaque surveillance | Opt-in observation, admin-local default, visible influence trace, inspect/reject/forget |
| Telemetry leaks sensitive evidence | Local default, minimal schemas, tier-gated export, redaction and negative tests |
| GUI bypasses CLI/domain invariants | Consume the same journal, policy gateway, package state, and verifier vocabulary |
| Cross-repo contracts drift | Pin versions, test vendored core parity, and make wire changes version-first |
| v2 scope combines M2 and M3 without focus | Treat package/control-plane foundations as the release spine; gate Team Brain and GUI slices behind them |

## Linear copy/paste block

**Title:** AIOS v2.0 — Verified Harness Control Plane

**Summary:** Productize AIOS's verified workflows as versioned harness packages
that can be planned, installed, inspected, evaluated, upgraded, repaired, and
removed safely across supported runtimes. Reuse the engineering harness for
portable policy/conformance and the workspace for product state, privacy,
reviews, journals, and UI. Borrow ECC's declarative profiles and managed
lifecycle patterns without importing its catalog scale or runtime-specific
policy duplication.

**User promise:** “I can install a trusted AIOS workflow, see exactly what it
will do and where its data goes, run it in my chosen supported runtime, verify
its output, and safely upgrade or remove it without losing my work.”

**In scope:**

- harness package schema and validator;
- outcome-oriented profiles and deterministic plan output;
- install state, doctor, repair, upgrade, and scoped uninstall;
- stable hook registry and evidence-backed runtime capability scorecard;
- five reference harness packages;
- behavioral evals and local quality/cost telemetry;
- governed maturity/memory controls;
- contract-aligned v2 inbox/GUI/runtime work;
- tier-safe Team Brain aggregation and package exchange;
- v1 migration and release hardening.

**Out of scope:** public marketplace, catalog-volume expansion, raw memory sync,
unattended external writes, implicit Brain protocol changes, and rewriting
proven update/journal foundations.

**Success:** five packages pass one contract; runtime claims have conformance
evidence; lifecycle fixtures prove no unowned overwrite; verifier state is
consistent across CLI/GUI/Brain; telemetry stays within tier; users can inspect
and forget learned context.

**Child issues:** V2-00 through V2-10 in this document.

## Decisions required before issue creation

1. Is “v2.0” the combined control-plane release described here, or should Team
   Brain aggregation remain a separately named milestone?
2. Which five workflows are the reference packages? The proposed set favors
   existing, well-tested operational value.
3. Is package distribution initially plain versioned files with integrity
   hashes, or signed artifacts? Do not block local package validation on a
   marketplace decision.
4. Which root workspace hooks can adopt the existing normalized protocol
   without changing its wire shape?
5. What local telemetry is useful enough to justify retention, and what is its
   default retention period?
6. Which deferred inbox issues still match the current authority and journal
   architecture after re-triage?

## Source pointers

AIOS:

- `aios-engineering-harness/hooks/PROTOCOL.md`
- `aios-engineering-harness/evals/CONTRACT.md`
- `aios-engineering-harness/docs/runtime-conformance.md`
- `aios-workspace/docs/product-roadmap-three-milestones.md`
- `aios-workspace/docs/release-status-v1.md`
- `aios-workspace/docs/v1-operator-loop/README.md`
- `aios-workspace/docs/v1-operator-loop/domains/maturity-loop.md`
- `aios-workspace/scripts/update.mjs`
- `aios-workspace/scripts/update/merge.mjs`
- `aios-workspace/gui/server/runtime-adapters/`
- `aios-workspace/src/operator-loop/inbox/`

ECC:

- [Repository overview](https://github.com/affaan-m/ECC)
- [Install profiles](https://github.com/affaan-m/ECC/blob/main/manifests/install-profiles.json)
- [Install/apply implementation](https://github.com/affaan-m/ECC/blob/main/scripts/install-apply.js)
- [CLI lifecycle](https://github.com/affaan-m/ECC/blob/main/scripts/ecc.js)
- [Hook system](https://github.com/affaan-m/ECC/blob/main/hooks/README.md)
- [Adapter compliance](https://github.com/affaan-m/ECC/blob/main/scripts/lib/harness-adapter-compliance.js)
- [OpenCode mapping](https://github.com/affaan-m/ECC/blob/main/.opencode/README.md)
- [Unified memory](https://github.com/affaan-m/ECC/blob/main/skills/unified-memory/SKILL.md)
- [Continuous learning](https://github.com/affaan-m/ECC/blob/main/skills/continuous-learning-v2/SKILL.md)
- [Contract-first workflow](https://github.com/affaan-m/ECC/blob/main/skills/contract-first/SKILL.md)
- [Eval workflow](https://github.com/affaan-m/ECC/blob/main/skills/eval-harness/SKILL.md)
