---
name: outbound-comms-guard
description: Configure and verify deterministic pre-command gates for email and WhatsApp sends, including frontmatter leakage, explicit account selection, recipient allowlists, send-enabled policy, and message linting. Use when outbound communication must be enforced by hooks rather than memory, after a send incident, or when installing the engineering harness around gog or wacli commands.
triggers:
  - outbound comms guard
  - email send guard
  - WhatsApp send guard
  - prevent accidental sends
  - frontmatter leak
---

# Outbound Comms Guard

Use a hook for automatic enforcement. Skill prose is not a control.

1. Create `.harness/outbound-comms.json` from [policy.md](references/policy.md); never put secrets in it.
2. Register `outbound-comms-guard.py` on normalized `pre_command` events for every installed runtime.
3. Run `python3 evals/outbound-comms-guard.test.py`.
4. Smoke-test only fixture or dry-run commands. Do not send a real message during installation.

Matching send commands fail closed when policy, body, account, or recipient cannot be resolved. Non-send and read-only commands pass without requiring policy.
