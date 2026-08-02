# Policy

Store this at `.harness/outbound-comms.json`:

```json
{
  "version": 1,
  "send_enabled": false,
  "email": {"account": "sender@example.com", "allowlist": ".harness/email-allowlist.txt"},
  "whatsapp": {"allowlist": ".harness/whatsapp-allowlist.txt"},
  "lint_command": ["python3", "tools/comms-lint.py"]
}
```

Allowlist files contain one normalized email address or E.164 phone number per line. Blank lines and `#` comments are ignored. `lint_command` is optional; when configured it receives the resolved message on stdin and must exit zero. Set `send_enabled` only after the allowlists exist and tests pass.
