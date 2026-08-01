#!/usr/bin/env python3
import json, subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "hooks/outbound-comms-guard.py"


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name)
        (self.root / ".harness").mkdir()
        (self.root / ".harness/email.txt").write_text("ok@example.com\n")
        (self.root / ".harness/wa.txt").write_text("+15551234567\n")
        (self.root / ".harness/outbound-comms.json").write_text(json.dumps({"version": 1, "send_enabled": True, "email": {"account": "me@example.com", "allowlist": ".harness/email.txt"}, "whatsapp": {"allowlist": ".harness/wa.txt"}}))
    def tearDown(self): self.tmp.cleanup()
    def run_guard(self, command):
        event = {"protocol_version": "1.1", "event": "pre_command", "runtime": {"name": "test"}, "cwd": str(self.root), "command": command}
        return subprocess.run(["python3", str(GUARD)], input=json.dumps(event), text=True, capture_output=True)
    def test_non_send_allows(self): self.assertEqual(self.run_guard("gog gmail search test").returncode, 0)
    def test_clean_email_allows(self): self.assertEqual(self.run_guard("gog gmail send --to ok@example.com -a me@example.com --body 'Hello'").returncode, 0)
    def test_prefixed_email_is_still_gated(self): self.assertEqual(self.run_guard("cd /tmp && gog gmail send --to no@example.com -a me@example.com --body Hello").returncode, 2)
    def test_frontmatter_blocks(self):
        (self.root / "draft.md").write_text("---\nnote: private\n---\nHello\n")
        self.assertEqual(self.run_guard("gog gmail send --to ok@example.com -a me@example.com --body-file draft.md").returncode, 2)
    def test_unknown_recipient_blocks(self): self.assertEqual(self.run_guard("gog gmail send --to no@example.com -a me@example.com --body Hello").returncode, 2)
    def test_whatsapp_allowlist(self):
        self.assertEqual(self.run_guard("wacli send --to +15551234567 --message Hello").returncode, 0)
        self.assertEqual(self.run_guard("wacli send --to +15550000000 --message Hello").returncode, 2)
    def test_configured_lint_is_fail_closed(self):
        policy = json.loads((self.root / ".harness/outbound-comms.json").read_text())
        policy["lint_command"] = ["python3", "-c", "import sys; sys.exit(1)"]
        (self.root / ".harness/outbound-comms.json").write_text(json.dumps(policy))
        self.assertEqual(self.run_guard("gog gmail send --to ok@example.com -a me@example.com --body Hello").returncode, 2)


if __name__ == "__main__": unittest.main()
