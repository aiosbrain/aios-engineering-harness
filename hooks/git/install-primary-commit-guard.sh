#!/usr/bin/env bash
#
# install-primary-commit-guard.sh — idempotently install pre-commit-primary-guard
# into a repo's .git/hooks/pre-commit, chaining any pre-existing hook.
#
# Usage:  hooks/git/install-primary-commit-guard.sh [repo-root]
#         (defaults to the current git repo)
#
# Idempotent: re-running is a no-op once installed. If a DIFFERENT pre-commit hook
# already exists, it is preserved as `.git/hooks/pre-commit.chained` and exec'd by
# the guard on success (so a secrets/leak gate keeps running).
set -euo pipefail

SRC_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
GUARD_SRC="$SRC_DIR/pre-commit-primary-guard"
[[ -f "$GUARD_SRC" ]] || { echo "install-primary-commit-guard: missing $GUARD_SRC" >&2; exit 1; }

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
[[ -n "$REPO_ROOT" ]] || { echo "install-primary-commit-guard: not a git repo" >&2; exit 1; }

HOOKS_DIR="$(git -C "$REPO_ROOT" rev-parse --git-path hooks 2>/dev/null)"
[[ "$HOOKS_DIR" = /* ]] || HOOKS_DIR="$REPO_ROOT/$HOOKS_DIR"
mkdir -p "$HOOKS_DIR"
MARKER="pre-commit-primary-guard"

# Install as BOTH pre-commit (ordinary commits) and pre-merge-commit (non-ff merge
# commits) so strict policy can genuinely force ff-only advancement of the primary.
for hook in pre-commit pre-merge-commit; do
  TARGET="$HOOKS_DIR/$hook"
  if [[ -f "$TARGET" ]] && grep -q "$MARKER" "$TARGET" 2>/dev/null; then
    echo "[harness] primary-commit guard already installed at $TARGET"
    continue
  fi
  # Preserve a pre-existing, unrelated hook of the same name so the guard chains it.
  if [[ -e "$TARGET" ]] && ! grep -q "$MARKER" "$TARGET" 2>/dev/null; then
    cp "$TARGET" "$HOOKS_DIR/$hook.chained"
    chmod +x "$HOOKS_DIR/$hook.chained"
    echo "[harness] preserved existing $hook hook -> $HOOKS_DIR/$hook.chained"
  fi
  cp "$GUARD_SRC" "$TARGET"
  chmod +x "$TARGET"
  echo "[harness] installed primary-commit guard -> $TARGET"
done
