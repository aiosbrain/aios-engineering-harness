#!/usr/bin/env python3
"""Fail-closed pre_command guard for configured gog/wacli sends."""
from __future__ import annotations
import json, re, shlex, subprocess, sys
from pathlib import Path

FRONTMATTER = re.compile(r"\A\s*---\s*\n(?:(?!\n---\s*$).)*\n---\s*$", re.M | re.S)


def block(message: str) -> int:
    print(f"BLOCKED outbound communication: {message}", file=sys.stderr)
    return 2


def values(args: list[str], flag: str) -> list[str]:
    out = []
    for i, item in enumerate(args):
        if item == flag and i + 1 < len(args): out.append(args[i + 1])
        elif item.startswith(flag + "="): out.append(item.split("=", 1)[1])
    return out


def outbound_slice(args: list[str]) -> tuple[str | None, list[str]]:
    matches: list[tuple[str, int]] = []
    for index in range(len(args)):
        if args[index:index + 3] == ["gog", "gmail", "send"]: matches.append(("email", index))
        if args[index:index + 2] == ["wacli", "send"]: matches.append(("whatsapp", index))
    if not matches: return None, args
    if len(matches) != 1: return "multiple", args
    channel, start = matches[0]
    end = len(args)
    for index in range(start, len(args)):
        if args[index] in {";", "&&", "||", "|"}:
            end = index
            break
    return channel, args[start:end]


def allowlist(path: Path) -> set[str]:
    return {line.strip().lower() for line in path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")}


def lint_message(policy: dict, text: str, root: Path) -> str | None:
    command = policy.get("lint_command")
    if command is None:
        return None
    if not isinstance(command, list) or not command or not all(isinstance(item, str) and item for item in command):
        return "lint_command must be a non-empty string array"
    try:
        result = subprocess.run(command, cwd=root, input=text, text=True, capture_output=True, timeout=10)
    except Exception as exc:
        return f"message lint could not run: {exc}"
    if result.returncode != 0:
        return f"message lint failed: {(result.stderr or result.stdout).strip()[:500]}"
    return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
        if event.get("event") != "pre_command": return 0
        command = event.get("command", "")
        args = shlex.split(command)
    except Exception:
        return 3
    channel_name, args = outbound_slice(args)
    if channel_name is None: return 0
    if channel_name == "multiple": return block("multiple outbound sends in one shell command are not reviewable")
    email = channel_name == "email"
    whatsapp = channel_name == "whatsapp"
    root = Path(event.get("cwd") or ".")
    policy_path = root / ".harness/outbound-comms.json"
    if not policy_path.exists():
        return 0
    try:
        policy = json.loads(policy_path.read_text())
        if policy.get("version") != 1 or policy.get("send_enabled") is not True:
            return block("send is disabled or policy version is invalid")
        channel = policy["email" if email else "whatsapp"]
        allowed = allowlist(root / channel["allowlist"])
    except Exception as exc:
        return block(f"policy or allowlist is unreadable: {exc}")
    if email:
        accounts = values(args, "--account") + values(args, "-a")
        if accounts != [channel.get("account")]: return block("explicit configured email account is required")
        recipients = values(args, "--to") + values(args, "--cc") + values(args, "--bcc")
        normalized = [v.strip().lower() for group in recipients for v in group.split(",") if v.strip()]
        if not normalized or any(item not in allowed for item in normalized): return block("every email recipient must be allowlisted")
        bodies = values(args, "--body") + values(args, "--body-html")
        files = values(args, "--body-file") + values(args, "--body-html-file")
        try: bodies += [(root / path).read_text() if not Path(path).is_absolute() else Path(path).read_text() for path in files]
        except Exception as exc: return block(f"body source is unreadable: {exc}")
        if not bodies: return block("resolvable body text is required")
        if any(FRONTMATTER.search(body) for body in bodies): return block("body contains YAML frontmatter")
        lint_error = lint_message(policy, "\n".join(bodies), root)
        if lint_error: return block(lint_error)
    else:
        recipients = values(args, "--to")
        if len(recipients) != 1 or recipients[0].lower() not in allowed: return block("one allowlisted E.164 WhatsApp recipient is required")
        messages = values(args, "--message") + values(args, "--caption")
        if not messages: return block("resolvable WhatsApp message text is required")
        if any(FRONTMATTER.search(message) for message in messages): return block("message contains YAML frontmatter")
        lint_error = lint_message(policy, "\n".join(messages), root)
        if lint_error: return block(lint_error)
    return 0


if __name__ == "__main__": sys.exit(main())
