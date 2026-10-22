#!/usr/bin/env bash
# bun-trust-probe.sh — HOLD gate for the eMudhra CA compromise (2026-10-20).
#
# Bun ships its own root store. Through 1.4.3 it still trusts certificates chained to the
# compromised eMudhra intermediates, so anything a Bun process sends over HTTPS (OpenCode's
# provider keys included: OpenCode is a compiled Bun binary) can be intercepted. This script
# exits 1 while the Bun on PATH accepts a forged chain, which keeps the hold in place until the
# pinned BUN_VERSION is a release that carries oven-sh/bun#46300.
#
# Exit codes:
#   0  every forged host was REACHED and refused with a certificate error, and the control passed
#   1  Bun trusted a forged chain (the hold stays)
#   2  inconclusive: a host was unreachable, or failed for a non-certificate reason. A DNS outage,
#      a timeout, a proxy, or the demo hosts going away must never read as "Bun is fixed".
set -euo pipefail

BUN="${BUN:-bun}"
FORGED=(
  https://dv-g3b-emudhra.we-have-a-problem.com/
  https://dv-g3b-aaa-emudhra.we-have-a-problem.com/
)
CONTROL=https://example.com/

# Prints one of: TRUSTED | REFUSED:<code> | UNREACHABLE:<code> | ERROR:<code>
# Step 1 fetches with verification OFF: if that fails, the host is not reachable and nothing can
# be concluded. Step 2 fetches with verification ON. Only an error whose code is a certificate
# verification failure counts as a refusal.
probe() {
  "$BUN" -e '
    const url = process.argv[1];
    const CERT = new Set(["CERT_REVOKED", "UNABLE_TO_GET_ISSUER_CERT_LOCALLY", "UNABLE_TO_GET_ISSUER_CERT",
      "UNABLE_TO_VERIFY_LEAF_SIGNATURE", "CERT_UNTRUSTED", "SELF_SIGNED_CERT_IN_CHAIN",
      "DEPTH_ZERO_SELF_SIGNED_CERT", "CERT_SIGNATURE_FAILURE", "CERT_CHAIN_TOO_LONG"]);
    const code = (e) => String(e?.code ?? e?.cause?.code ?? e?.name ?? "unknown");
    const opts = (insecure) => ({ signal: AbortSignal.timeout(15000), ...(insecure ? { tls: { rejectUnauthorized: false } } : {}) });
    try { await fetch(url, opts(true)); } catch (e) { console.log("UNREACHABLE:" + code(e)); process.exit(0); }
    try { await fetch(url, opts(false)); console.log("TRUSTED"); }
    catch (e) { const c = code(e); console.log((CERT.has(c) ? "REFUSED:" : "ERROR:") + c); }
  ' "$1" 2>/dev/null || echo "ERROR:bun-exited"
}

echo "bun $("$BUN" --revision)"
trusted=0
inconclusive=0
for url in "${FORGED[@]}"; do
  verdict="$(probe "$url")"
  echo "$verdict  $url"
  case "$verdict" in
    TRUSTED) trusted=1 ;;
    REFUSED:*) ;;
    *) inconclusive=1 ;;
  esac
done
verdict="$(probe "$CONTROL")"
echo "$verdict  $CONTROL (control)"
[ "$verdict" = TRUSTED ] || inconclusive=1

if [ "$trusted" -ne 0 ]; then
  echo "HOLD: this Bun trusts a forged eMudhra chain. Bump BUN_VERSION to a release with the fix." >&2
  exit 1
fi
if [ "$inconclusive" -ne 0 ]; then
  echo "INCONCLUSIVE: a host was unreachable or failed for a non-certificate reason; the hold stays." >&2
  exit 2
fi
echo "bun refuses the forged chains: hold can be lifted"
