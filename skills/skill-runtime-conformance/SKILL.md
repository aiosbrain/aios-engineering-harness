---
name: skill-runtime-conformance
description: Audit declared agent skills across Claude, Codex, OpenCode, and Cursor for missing, stale, partial, orphaned, or invalid projections. Use when publishing a skill to multiple runtimes, investigating why one runtime cannot discover a skill, checking generated skill copies in CI, or validating a repository's .skill-runtimes.json manifest.
triggers:
  - skill runtime conformance
  - skill parity
  - skill drift
  - publish this skill to every runtime
  - why can one runtime not see this skill
---

# Skill Runtime Conformance

Treat the manifest as publication intent. Do not infer intent from generated copies: deleting every copy must still fail.

1. Read `.skill-runtimes.json` and the repository instructions.
2. Run `python3 scripts/audit.py check --root <repo> --config <manifest>` from this skill directory. Add `--json` for machine-readable evidence.
3. Classify every finding as `missing`, `stale`, `partial`, `orphan`, `invalid`, or `unsupported`.
4. Repair drift with the repository's declared generator. Never hand-edit generated copies.
5. Re-run the audit and the repository's focused synchronization tests.

Use `matrix` instead of `check` for a non-blocking inventory. `check` exits `0` when conformant, `1` for drift, and `2` for invalid configuration or unreadable catalogs.

Read [runtime-layouts.md](references/runtime-layouts.md) before adding a runtime or changing the manifest contract.
