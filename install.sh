#!/usr/bin/env bash
# .harness/install.sh — idempotent installer that wires the vendored harness into a repo.
#
# Safe by design:
#   - NEVER overwrites an existing runtime config — writes <file>.harness-incoming instead.
#   - seeds AGENTS.md / CONSTITUTION.md / .harness/check only when absent.
#   - re-running is a no-op once everything is in place.
#   - strips the template `$comment` from installed JSON configs.
#
# Usage:
#   .harness/install.sh [--repo <dir>] [--runtime claude-code|codex|opencode|cursor]... [--all]
# Default: auto-detect runtimes by existing .claude/.codex/.opencode/.cursor dirs;
#          fall back to claude-code if none are present.
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT=""
declare -a WANT=()
ALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      [ -n "${2:-}" ] || { echo "install: --repo requires a directory" >&2; exit 2; }
      REPO_ROOT="$2"; shift 2
      ;;
    --runtime)
      [ -n "${2:-}" ] || { echo "install: --runtime requires a name" >&2; exit 2; }
      WANT+=("$2"); shift 2
      ;;
    --all) ALL=1; shift ;;
    -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install: unknown arg '$1'" >&2; exit 2 ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  case "$HARNESS_DIR" in
    */.harness) REPO_ROOT="$(dirname "$HARNESS_DIR")" ;;
    *) REPO_ROOT="$(git -C "$HARNESS_DIR" rev-parse --show-toplevel 2>/dev/null || pwd)" ;;
  esac
fi
REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
echo "[harness] repo=$REPO_ROOT harness=$HARNESS_DIR"

# Validate every explicit --runtime even when --all is also present.
for rt in "${WANT[@]}"; do
  case "$rt" in
    claude-code|codex|opencode|cursor) ;;
    *) echo "[harness] unknown runtime '$rt'" >&2; exit 2 ;;
  esac
done

if [ "$ALL" = 1 ]; then WANT=(claude-code codex opencode cursor); fi
if [ ${#WANT[@]} -eq 0 ]; then
  [ -d "$REPO_ROOT/.claude" ]   && WANT+=(claude-code)
  [ -d "$REPO_ROOT/.codex" ]    && WANT+=(codex)
  [ -d "$REPO_ROOT/.opencode" ] && WANT+=(opencode)
  [ -d "$REPO_ROOT/.cursor" ]   && WANT+=(cursor)
  [ ${#WANT[@]} -eq 0 ] && WANT=(claude-code)
fi

# Keep repeated --runtime arguments idempotent too.
declare -a UNIQUE_WANT=()
for rt in "${WANT[@]}"; do
  FOUND=0
  if [ ${#UNIQUE_WANT[@]} -gt 0 ]; then
    for existing in "${UNIQUE_WANT[@]}"; do
      [ "$existing" = "$rt" ] && FOUND=1
    done
  fi
  [ "$FOUND" = 1 ] || UNIQUE_WANT+=("$rt")
done
WANT=("${UNIQUE_WANT[@]}")

command -v jq >/dev/null 2>&1 || {
  echo "install: jq is required to normalize runtime configuration" >&2
  exit 3
}

echo "[harness] runtimes: ${WANT[*]}"

path_exists() {
  [ -e "$1" ] || [ -L "$1" ]
}

reject_symlink_dir() {
  if [ -L "$1" ]; then
    echo "install: refusing symlinked destination directory $1" >&2
    return 1
  fi
}

seed() {  # seed <src> <dst> — copy only when dst is absent
  if path_exists "$2"; then echo "[harness] keep   $2"; else mkdir -p "$(dirname "$2")"; cp "$1" "$2"; echo "[harness] seed   $2"; fi
}

install_json() {  # install_json <src> <dst> — strip $comment; never overwrite an existing file
  local tmp; tmp="$(mktemp)"
  if ! jq 'del(."$comment")' "$1" > "$tmp"; then
    rm -f "$tmp"
    echo "install: failed to normalize $1" >&2
    return 1
  fi
  if ! path_exists "$2"; then
    mkdir -p "$(dirname "$2")"; cp "$tmp" "$2"; echo "[harness] write  $2"
  elif cmp -s "$tmp" "$2"; then
    echo "[harness] ok     $2"
  else
    if path_exists "$2.harness-incoming"; then
      rm -f "$tmp"
      echo "install: refusing to overwrite existing merge artifact $2.harness-incoming" >&2
      return 1
    fi
    cp "$tmp" "$2.harness-incoming"; echo "[harness] MERGE  $2 exists -> wrote $2.harness-incoming (merge its keys; never auto-overwritten)"
  fi
  rm -f "$tmp"
}

# Abort before any writes if pending configuration merge work already exists.
reject_symlink_dir "$REPO_ROOT/.harness"
for rt in "${WANT[@]}"; do
  case "$rt" in
    claude-code)
      reject_symlink_dir "$REPO_ROOT/.claude"
      reject_symlink_dir "$REPO_ROOT/.claude/skills"
      reject_symlink_dir "$REPO_ROOT/.claude/agents"
      CONFIG_DST="$REPO_ROOT/.claude/settings.json"
      ;;
    codex)
      reject_symlink_dir "$REPO_ROOT/.agents"
      reject_symlink_dir "$REPO_ROOT/.agents/skills"
      reject_symlink_dir "$REPO_ROOT/.codex"
      CONFIG_DST="$REPO_ROOT/.codex/hooks.json"
      ;;
    opencode)
      reject_symlink_dir "$REPO_ROOT/.opencode"
      reject_symlink_dir "$REPO_ROOT/.opencode/plugins"
      reject_symlink_dir "$REPO_ROOT/.opencode/skills"
      CONFIG_DST="$REPO_ROOT/opencode.json"
      ;;
    cursor)
      reject_symlink_dir "$REPO_ROOT/.cursor"
      reject_symlink_dir "$REPO_ROOT/.cursor/rules"
      CONFIG_DST="$REPO_ROOT/.cursor/hooks.json"
      ;;
  esac
  if path_exists "$CONFIG_DST.harness-incoming"; then
    echo "install: refusing to overwrite existing merge artifact $CONFIG_DST.harness-incoming" >&2
    exit 1
  fi
done

# Make every shell entrypoint executable.
find "$HARNESS_DIR/hooks" "$HARNESS_DIR/adapters" -type f \
  \( -name '*.sh' -o -path '*/hooks/git/*' \) -exec chmod +x {} +

# Contracts + the verification gate (seed only).
seed "$HARNESS_DIR/AGENTS.md" "$REPO_ROOT/AGENTS.md"
seed "$HARNESS_DIR/CONSTITUTION.md" "$REPO_ROOT/CONSTITUTION.md"
seed "$HARNESS_DIR/check" "$REPO_ROOT/.harness/check"

for rt in "${WANT[@]}"; do
  case "$rt" in
    claude-code)
      mkdir -p "$REPO_ROOT/.claude/skills" "$REPO_ROOT/.claude/agents"
      cp -R "$HARNESS_DIR"/skills/. "$REPO_ROOT/.claude/skills/"
      cp "$HARNESS_DIR"/agents/*.md "$REPO_ROOT/.claude/agents/"
      install_json "$HARNESS_DIR/adapters/claude-code/settings.json" "$REPO_ROOT/.claude/settings.json" ;;
    codex)
      mkdir -p "$REPO_ROOT/.agents/skills"
      cp -R "$HARNESS_DIR"/skills/. "$REPO_ROOT/.agents/skills/"
      install_json "$HARNESS_DIR/adapters/codex/hooks.json" "$REPO_ROOT/.codex/hooks.json" ;;
    opencode)
      mkdir -p "$REPO_ROOT/.opencode/plugins" "$REPO_ROOT/.opencode/skills"
      cp "$HARNESS_DIR/adapters/opencode/plugin/harness.ts" "$REPO_ROOT/.opencode/plugins/harness.ts"
      cp "$HARNESS_DIR/adapters/opencode/normalize.ts" "$REPO_ROOT/.opencode/normalize.ts"
      cp -R "$HARNESS_DIR"/skills/. "$REPO_ROOT/.opencode/skills/"
      install_json "$HARNESS_DIR/adapters/opencode/opencode.json" "$REPO_ROOT/opencode.json" ;;
    cursor)
      mkdir -p "$REPO_ROOT/.cursor/rules"
      cp -R "$HARNESS_DIR"/adapters/cursor/rules/. "$REPO_ROOT/.cursor/rules/"
      install_json "$HARNESS_DIR/adapters/cursor/hooks.json" "$REPO_ROOT/.cursor/hooks.json" ;;
  esac
  echo "[harness] wired  $rt"
done

# Worktree commit guard (git repos only).
if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  "$HARNESS_DIR/hooks/git/install-primary-commit-guard.sh" "$REPO_ROOT"
fi

echo "[harness] done — set .harness/check to your real gate and fill the AGENTS.md TODOs."
