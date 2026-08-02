---
name: npm-publish
description: Prepare, authenticate, publish, and verify npm packages without confusing passkey/WebAuthn accounts with TOTP, and configure GitHub Actions Trusted Publishing with OIDC. Use for npm publish, EOTP or browser-auth failures, package-release preparation, npm Trusted Publishing, provenance, or staged publish machinery. Do not publish when the user requested only a PR or dry run.
triggers:
  - npm publish
  - EOTP
  - trusted publishing
  - publish the package
  - npm provenance
---

# npm Publish

## Establish authority

Distinguish `prepare`, `publish`, and `configure trusted publishing`. Never turn preparation into a live publish. Resolve the package, registry, exact commit, version, tag, access, and workspace selector.

## Preflight

1. Require a clean checkout at the intended merged or tagged commit.
2. Verify package name, version, `private`, `publishConfig.access`, repository, license, and workspace dependency versions.
3. Run the repository gate and `npm pack --dry-run`; inspect the complete file list.
4. Reject a version already published or dishonestly reused after its tag.
5. For interactive publishing, determine whether authentication is passkey/browser or TOTP. An `EOTP` string alone does not prove a TOTP exists.

For passkey/browser authentication in a non-interactive agent shell, allocate a pseudo-TTY, surface the npm authentication URL, let the user approve it, and wait for that exact process. Never ask for an authenticator code unless the account actually uses TOTP.

## Trusted Publishing

Prefer GitHub OIDC for recurring release automation. Follow [trusted-publishing.md](references/trusted-publishing.md). Keep the first publication of a new package explicit: npm cannot configure a trusted publisher for a package that does not exist.

## Verify

Query the registry for the exact version and dist-tag, inspect provenance when required, and report the published commit. A successful workflow invocation is not publication evidence.
