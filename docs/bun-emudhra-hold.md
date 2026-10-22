# Hold: Bun and the eMudhra CA compromise

**Status: ON HOLD since 2026-10-22.** Lift it only when the conditions below are met.

## Why

On 2026-10-20 Mozilla disclosed that eight eMudhra intermediate CAs were generated with weak keys
whose private keys can be recovered from the public certificates. Anyone can forge a certificate for
any domain that chains to `emSign Root TLS CA - G3`, or through Sectigo's cross-signed
`AAA Certificate Services`. Browsers, Node (22.23.4 / 24.22.1 / 26.12.1), Python certifi
(2026.10.19), Go and Deno have shipped fixes.

Bun carries its own root store and does not. Measured on 2026-10-22:

| Bun | `dv-g3b-emudhra` | `dv-g3b-aaa-emudhra` |
|---|---|---|
| 1.2.23 (this repo's `BUN_VERSION`) | **TRUSTED** | refused, `UNABLE_TO_GET_ISSUER_CERT_LOCALLY` |
| 1.4.3 (latest release) | **TRUSTED** | **TRUSTED** |
| 1.4.4-canary.1+963452075 | refused, `CERT_REVOKED` | refused, `CERT_REVOKED` |

OpenCode is a compiled Bun executable: `opencode` 1.18.18 embeds Bun 1.3.14 and **trusts** the
forged host (`BUN_BE_BUN=1 opencode -e "fetch(...)"`). Any provider key OpenCode sends is exposed
until OpenCode is rebuilt on a fixed Bun.

None of `--use-system-ca`, `NODE_USE_SYSTEM_CA=1` or `--use-openssl-ca` removes the bundled roots on
1.4.3: each still fetched the forged host in a local test on 2026-10-22, and oven-sh/bun#46302's
description says `--use-openssl-ca` still adds the bundled set. `NODE_EXTRA_CA_CERTS` only adds.

## Upstream

- oven-sh/bun#46356: user report, open.
- oven-sh/bun#46159: root store update, merged 2026-10-20.
- oven-sh/bun#46300: blocked-key check + NSS 3.131.1, merged 2026-10-21. **This is the fix.**
- oven-sh/bun#46302: make `--use-openssl-ca` drop the bundled roots, open.
- Status page: https://emudhra.we-have-a-problem.com/ (lists Bun as "pending").

## The gate

`scripts/bun-trust-probe.sh` asks the Bun on `PATH` to fetch both forged hosts and a control.
Each forged host is first fetched with verification **off**, so a host that cannot be reached is
reported as unreachable instead of being mistaken for a refusal. Only a certificate-verification
error counts as refused.

| Exit | Meaning |
|---|---|
| 0 | both forged hosts reached and refused with a certificate error, control reachable |
| 1 | Bun trusted a forged chain: the hold stays |
| 2 | inconclusive (DNS, timeout, proxy, hosts gone, non-certificate error): the hold stays |

CI runs it on `BUN_VERSION` as the `Bun trust-store hold (eMudhra)` job, and `./check` runs it on
the local Bun. **How the hold is enforced:** the README banner, a red CI job, and a red `./check`.
The job is made a required status check on `main` once this lands, so no other change merges
until the hold lifts; the lift PR itself turns it green by bumping `BUN_VERSION`.

## Lifting the hold

1. A Bun release (not canary) that contains #46300 is published.
2. Bump `BUN_VERSION` in `.github/workflows/ci.yml` to it; the hold job goes green. If it exits
   2 instead, the demo hosts may be gone: check https://emudhra.we-have-a-problem.com/ and the
   upstream release notes, and substitute any still-published forged-chain test host before
   lifting. Do not lift on an inconclusive run.
3. Run `bash scripts/bun-trust-probe.sh` locally after `bun upgrade`; it must print
   "hold can be lifted".
4. Upgrade OpenCode once it ships on that Bun, and re-run
   `BUN_BE_BUN=1 opencode -e "fetch('https://dv-g3b-emudhra.we-have-a-problem.com/').then(()=>console.log('TRUSTED')).catch(e=>console.log('REFUSED', e.code))"`.
5. Remove the README banner and the required-check setting, then mark this file Lifted with the date.
