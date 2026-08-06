#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v python3 >/dev/null 2>&1 || {
  echo "linear-routing-guard: python3 not found" >&2
  exit 3
}
exec python3 "$SCRIPT_DIR/guard-linear-routing.py"
