---
name: aios-linear
description: Route Linear work through the workspace-bound AIOS CLI.
triggers:
  - Linear
  - issue tracker
  - create issue
  - update issue
  - comment on issue
---

# AIOS Linear routing

Use the public `aios linear` command family for Linear reads and writes. Do not call
the Linear API directly, use a generic Linear CLI, mutate through Linear MCP, or run
a copied workspace-specific script.

The CLI resolves its workspace in this order: explicit `--repo`, stamped current
directory, `AIOS_AGENT_WORKSPACE`, then the XDG default workspace. Credentials stay
in that workspace's local encrypted secret store; never print or copy them.

Run `aios linear status --json` before work when connection state is uncertain. Use
`aios linear --help` for the available read, create, comment, assignment, state, and
relation operations. Read the exact issue back after every mutation and report any
verification mismatch instead of assuming success.
