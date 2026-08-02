# npm Trusted Publishing

Require all of the following:

- GitHub `permissions`: `contents: read` and `id-token: write`.
- `actions/setup-node` with `registry-url: https://registry.npmjs.org`.
- npm 11.5.1 or newer on the runner.
- Exact npm package settings for GitHub organization/user, repository, and workflow filename; organization case matters.
- An explicit workflow version input checked against `package.json` before publishing.
- The package's normal install, test, build, and pack gates before `npm publish`.
- No long-lived npm token when OIDC is in use.

For a new package: confirm the name, perform one authorized interactive publish, configure the trusted publisher on the resulting package page, then verify the workflow with the next version. Never publish an unscoped fallback name merely because the requested name is occupied.
