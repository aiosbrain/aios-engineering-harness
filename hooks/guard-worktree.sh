#!/bin/sh
# Portable worktree-discipline policy. Handles pre_edit AND pre_command.
# Exit 0 allow, 2 policy block, 3 evaluation failure.
#
# Enforces the worktree convention that harnesses running with full autonomy
# (Codex/OpenCode/Cursor/Claude) otherwise ignore: feature work must live in a
# dedicated linked git worktree, never on a branch checked out in the PRIMARY
# checkout. Automated agents were observed doing `git checkout -b <feature>` in
# the primary checkout and committing there — colliding with concurrent human
# work and producing duplicate PRs. This guard makes that structurally loud at
# the moment of the edit or the branching command, not just at commit time (the
# tracked pre-commit git-hook `hooks/git/pre-commit-primary-guard` is the
# commit-time backstop for paths this agent hook never sees).
#
# Rules, only when the target repo is the PRIMARY checkout (no-op in worktrees):
#   pre_command  — block creating a branch (`git checkout -b`/`switch -c`/`branch <new>`)
#                  and block `git commit` on a non-default branch.
#   pre_edit     — block edits when HEAD is a non-default branch (you branched into
#                  the primary). Editing on the default branch is allowed (config /
#                  rare hotfix); basenames in HARNESS_PRIMARY_EXEMPT are always allowed.
#
# Overrides: HARNESS_ALLOW_PRIMARY_CHECKOUT=1 disables the guard entirely.
#            HARNESS_DEFAULT_BRANCH (default `main`) sets the allowed primary branch.
#            HARNESS_PRIMARY_EXEMPT (default `aios.yaml`) is a space-separated basename
#            allowlist for files that legitimately live in the primary checkout.
set -u

[ "${HARNESS_ALLOW_PRIMARY_CHECKOUT:-0}" = "1" ] && exit 0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
INPUT=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 3

# The adapter wires this policy into both the edit matcher (pre_edit) and the bash
# matcher (pre_command); by the time we run, run-hook.sh has normalized the payload
# and set .event. Dispatch on that; anything else (post_edit/stop/unknown) is a no-op.
EVENT_NAME=$(printf '%s' "$INPUT" | jq -r '.event // empty' 2>/dev/null)
case "$EVENT_NAME" in
  pre_command) MODE=command ;;
  pre_edit)    MODE=edit ;;
  *)           exit 0 ;;
esac

EVENT=$(printf '%s' "$INPUT" | "$SCRIPT_DIR/prepare-event.sh" "$EVENT_NAME")
STATUS=$?
[ "$STATUS" -eq 4 ] && exit 0
[ "$STATUS" -eq 0 ] || exit 3

DEFAULT_BRANCH=${HARNESS_DEFAULT_BRANCH:-main}
EXEMPT_BASENAMES=${HARNESS_PRIMARY_EXEMPT:-aios.yaml}

# probe <dir> -> echoes "primary <branch>" | "worktree <branch>" | "none".
# Primary detection mirrors the tracked pre-commit guard: in the primary checkout
# the git dir equals the common git dir; in a linked worktree it is
# `<common>/worktrees/<name>`. Both paths are physically resolved (pwd -P) so a
# macOS /private↔/var symlink can't make the primary look like a worktree.
# Fail-open (none) when git cannot resolve the repo.
probe() {
  _d=$1
  _gd=$(git -C "$_d" rev-parse --absolute-git-dir 2>/dev/null) || { echo none; return; }
  _gd=$(cd "$_gd" 2>/dev/null && pwd -P) || { echo none; return; }
  _cd=$(git -C "$_d" rev-parse --git-common-dir 2>/dev/null) || { echo none; return; }
  case "$_cd" in
    /*) _cd=$(cd "$_cd" 2>/dev/null && pwd -P) ;;
    *)  _cd=$(cd "$_d" 2>/dev/null && cd "$_cd" 2>/dev/null && pwd -P) ;;
  esac
  [ -n "$_cd" ] || { echo none; return; }
  _br=$(git -C "$_d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)
  if [ "$_gd" = "$_cd" ]; then echo "primary $_br"; else echo "worktree $_br"; fi
}

block() {
  {
    echo "BLOCKED by guard-worktree: $1"
    echo "$2"
    echo "Fix: create a dedicated worktree instead —"
    echo "  aios worktree add feat/<name>        # (or: git worktree add -b feat/<name> ../<repo>-worktrees/<name> origin/${DEFAULT_BRANCH})"
    echo "Override for a genuine primary-checkout action: HARNESS_ALLOW_PRIMARY_CHECKOUT=1"
  } >&2
  exit 2
}

CWD=$(printf '%s' "$EVENT" | jq -r '.cwd // empty')
[ -n "$CWD" ] || CWD=$(pwd)

if [ "$MODE" = "command" ]; then
  CMD=$(printf '%s' "$EVENT" | jq -r '.command // empty') || exit 3
  [ -n "$CMD" ] || exit 3

  set -- $(probe "$CWD"); KIND=${1:-none}; BRANCH=${2:-}
  [ "$KIND" = "primary" ] || exit 0

  # Creating a branch in the primary checkout — the exact omo/Codex failure mode.
  if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+(checkout[[:space:]]+-[a-zA-Z]*b|switch[[:space:]]+-[a-zA-Z]*c)([[:space:]]|$)'; then
    block "creating a branch in the primary checkout (branch '$BRANCH')" \
      "\`git checkout -b\` / \`git switch -c\` in the primary checkout strands it on a feature branch and collides with concurrent work."
  fi
  # `git branch <newname>` (a bare `git branch` / `-a` / `--list` is a read — allow).
  if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+branch[[:space:]]+([^-][^;|&[:space:]]*)([[:space:]]|$)'; then
    block "creating a branch in the primary checkout (branch '$BRANCH')" \
      "Create feature branches as worktrees, not in the primary checkout."
  fi
  # Committing in the primary checkout (belt-and-suspenders with the git hook).
  # strict policy blocks every branch; default-ok blocks only non-default branches.
  if printf '%s' "$CMD" | grep -qE 'git[[:space:]]+commit([[:space:]]|$)'; then
    if [ "${HARNESS_PRIMARY_COMMIT_POLICY:-default-ok}" = "strict" ]; then
      block "committing in the primary checkout (branch '$BRANCH', strict policy)" \
        "The primary checkout only advances via \`git merge --ff-only\`; author commits in a worktree."
    elif [ "$BRANCH" != "$DEFAULT_BRANCH" ]; then
      block "committing on non-default branch '$BRANCH' in the primary checkout" \
        "Feature commits belong in a worktree, never on a branch committed in the primary checkout."
    fi
  fi
  exit 0
fi

# MODE = edit
FILE_PATHS=$(printf '%s' "$EVENT" | jq -r '.paths[]? | .path, (.from // empty)' | awk 'NF && !seen[$0]++') || exit 3
[ -n "$FILE_PATHS" ] || exit 0

# Probe the repo of the first edited path (fall back to CWD).
FIRST=$(printf '%s\n' "$FILE_PATHS" | head -n 1)
case "$FIRST" in
  /*) PROBE_DIR=$(dirname "$FIRST") ;;
  *)  PROBE_DIR="$CWD/$(dirname "$FIRST")" ;;
esac
[ -d "$PROBE_DIR" ] || PROBE_DIR="$CWD"

set -- $(probe "$PROBE_DIR"); KIND=${1:-none}; BRANCH=${2:-}
[ "$KIND" = "primary" ] || exit 0
[ "$BRANCH" = "$DEFAULT_BRANCH" ] && exit 0   # editing on the default branch in primary is allowed

# On a non-default branch in the primary checkout: block unless every edited path
# is an explicitly exempt basename.
for p in $FILE_PATHS; do
  base=$(basename "$p")
  exempt=0
  for e in $EXEMPT_BASENAMES; do [ "$base" = "$e" ] && exempt=1; done
  [ "$exempt" = "1" ] && continue
  block "editing '$p' on non-default branch '$BRANCH' in the primary checkout" \
    "You are on a feature branch checked out in the primary checkout — feature work belongs in a linked worktree."
done
exit 0
