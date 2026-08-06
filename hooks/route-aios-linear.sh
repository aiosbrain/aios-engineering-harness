#!/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
command -v python3 >/dev/null 2>&1 || {
  echo "route-aios-linear: python3 not found" >&2
  exit 3
}
exec python3 "$SCRIPT_DIR/route-aios-linear.py"
