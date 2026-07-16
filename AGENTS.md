# AGENTS.md — template

> The repo↔agent contract, per the [AGENTS.md standard](https://agents.md) (read natively
> by Claude Code, Codex, Cursor, Zed, Amp, Copilot, opencode, and 20+ other tools).
> Replace the `TODO`s; delete these blockquote notes when you adopt it.
>
> **Two rules govern this file:**
> 1. **Slow facts only.** Build/test commands, conventions, architecture decisions —
>    things that change monthly, not hourly. Fast-changing facts (file locations,
>    signatures, data flows) should come from live tools (LSP, code search, MCP), not
>    from a doc that goes stale.
> 2. **Keep it under ~200 lines.** For every line ask: *would removing this cause an
>    agent to make a mistake?* If not, cut it. Overflow goes into path-scoped rules
>    files or skills.

## Project

`TODO:` one paragraph — what this system is, who it serves, the 2–3 architectural facts
an engineer must know before touching anything.

## Commands

```bash
# TODO: the real ones. Examples:
make setup          # install deps
make test           # full test suite — MUST pass before any commit
make test-fast      # quick loop for TDD
make lint           # lint + typecheck
make run            # run the app locally
```

## Conventions

- `TODO:` code style beyond what the formatter enforces
- `TODO:` how errors are handled / logged
- `TODO:` how database changes are made (and whether agents may make them)
- `TODO:` a "good example" file to copy for each major kind of component

## Boundaries

- Never edit: `TODO` (e.g. `.env*`, `migrations/**`, generated files, vendored code)
- Always ask before: `TODO` (e.g. deleting files, adding dependencies, touching auth)

## Verification

Definition of done for any change: `TODO` (e.g. `make lint && make test` green, plus
driving the affected flow end-to-end — not just the unit tests).

---

## Error ledger

> The compounding section. Whenever an agent makes a mistake a rule could have
> prevented, add the rule here (or promote it to a hook if it must be *guaranteed*).
> Date each entry. Prune entries that graduate into hooks or formatters.

- `YYYY-MM-DD` — `TODO: first entry`
