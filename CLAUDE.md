# CLAUDE.md — aios-engineering-harness

**Read [`AGENTS.md`](AGENTS.md) first.** It is the repo↔agent contract for every runtime
and it is not duplicated here: project shape, the three facts to know before touching
anything, the full Commands block, conventions, boundaries, verification, and the error
ledger all live there. This file adds only what is specific to Claude Code.

## Where things are

| You want to… | Go to |
|---|---|
| Understand the normalized hook protocol | `hooks/PROTOCOL.md` + `hooks/protocol.schema.json` |
| Translate a runtime's native tool events | `adapters/{claude-code,codex,cursor,opencode}/` |
| Know what is "core" vs a repo-local adapter point | `evals/CONTRACT.md` |
| Run or extend the eval lab | `evals/README.md`, `evals/run.sh` |
| Add or edit a skill | `skills/<name>/SKILL.md` (see `skills/skill-author/`) |
| Install the harness into a target repo | `install.sh`, `BOOTSTRAP.md` |
| See what the harness borrows and from where | `PROVENANCE.md` |
| Understand the non-negotiables | `CONSTITUTION.md` |

## Skills live in `skills/`, not `.claude/skills/`

This repo is the **source** of a skill pack, not a consumer of one. `install.sh` copies
`skills/<name>/SKILL.md` into the target repo's `.claude/skills/` (and the equivalent
location for Codex, Cursor, and OpenCode). Do not add a `.claude/skills/` directory here
and do not edit an installed copy in a consumer repo — edit `skills/<name>/SKILL.md` and
re-install.

The AIOS codebase analyzer recognizes this root pack layout through tracked
`skills/**/SKILL.md` manifests as well as installed `.claude/skills/` layouts. If another
counter misses the source-pack layout, fix that counter rather than duplicating the pack.

## One-command check

```bash
./check          # runs the repository CI workflows' gates, in CI job order
```

Everything `./check` runs is also spelled out individually in `AGENTS.md` § Commands, so
you can run one gate in isolation while iterating.

## Worktrees, not branches

Do agent work in a `git worktree` off `origin/main`, never on the primary checkout's
`main`. See `skills/git-master/SKILL.md`. Container convention:
`../aios-engineering-harness-worktrees/<short-task>`.

## Two rules that cost the most when broken

1. **A new `evals/*.test.{sh,py}` is not a check until it is listed in both
   `.github/workflows/ci.yml`'s `tests` job and `AGENTS.md` § Commands.** Wire the runner
   in the same commit that adds the test. Four suites once sat unwired for weeks, passing
   locally and never running on a PR.
2. **Never add native-payload parsing to a `hooks/*.sh` script.** Hooks parse the
   normalized protocol only; native translation belongs in the adapter.

The rest of the compounding rules are in `AGENTS.md` § Error ledger — add new ones there,
not here.
