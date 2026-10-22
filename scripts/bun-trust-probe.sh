#!/usr/bin/env bash
# bun-trust-probe.sh — HOLD gate for the eMudhra CA compromise (2026-10-20).
#
# Bun ships its own root store. Through 1.4.3 it still trusts certificates chained to the
# compromised eMudhra intermediates, so anything a Bun process sends over HTTPS (OpenCode's
# provider keys included: OpenCode is a compiled Bun binary) can be intercepted. This script
# exits non-zero while the Bun on PATH accepts a forged chain, which keeps CI red and the
# harness on HOLD until the pinned BUN_VERSION is a release that carries oven-sh/bun#46300.
#
# Pass = both forged hosts refused AND the control reachable. Refusing everything is not a pass.
set -euo pipefail

BUN="${BUN:-bun}"
FORGED=(
  https://dv-g3b-emudhra.we-have-a-problem.com/
  https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
)
CONTROL=https://example.com/

probe() {
  # Prints TRUSTED or REFUSED:<code>; never fails the shell itself.
  "$BUN" -e "fetch(process.argv[1], { signal: AbortSignal.timeout(15000) })
    .then(() => console.log('TRUSTED'))
    .catch((e) => console.log('REFUSED:' + (e.code || e.name)))" "$1" 2>/dev/null || echo "REFUSED:bun-error"
}

echo "bun $("$BUN" --revision)"
fail=0
for url in "${FORGED[@]}"; do
  verdict="$(probe "$url")"
  echo "$verdict  $url"
  [ "$verdict" = TRUSTED ] && fail=1
done
verdict="$(probe "$CONTROL")"
echo "$verdict  $CONTROL (control)"
[ "$verdict" = TRUSTED ] || { echo "control unreachable: the probe proves nothing" >&2; exit 2; }

if [ "$fail" -ne 0 ]; then
  echo "HOLD: this Bun trusts a forged eMudhra chain. Bump BUN_VERSION to a release with the fix." >&2
  exit 1
fi
echo "bun refuses the forged chains: hold can be lifted"
