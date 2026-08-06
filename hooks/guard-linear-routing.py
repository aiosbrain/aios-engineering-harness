#!/usr/bin/env python3
"""Scope-aware guard for the first-party `aios linear` route."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys


MUTATION_WORDS = {
    "add",
    "archive",
    "assign",
    "comment",
    "create",
    "delete",
    "move",
    "relation",
    "remove",
    "set",
    "state",
    "unarchive",
    "update",
}


def fail(message: str, code: int = 3) -> int:
    print(f"linear-routing-guard: {message}", file=sys.stderr)
    return code


def config_path() -> Path | None:
    root = os.environ.get("XDG_CONFIG_HOME", "").strip()
    if root:
        path = Path(root)
        if not path.is_absolute():
            return None
        return path / "aios" / "config.json"
    home = os.environ.get("HOME", "").strip()
    return Path(home) / ".config" / "aios" / "config.json" if home else None


def in_guard_scope(cwd: str, scopes: object) -> bool:
    if not isinstance(scopes, list):
        raise ValueError("guardScopes must be an array")
    current = Path(cwd).resolve(strict=False)
    for raw in scopes:
        if not isinstance(raw, str) or not raw or not Path(raw).is_absolute():
            raise ValueError("guardScopes entries must be absolute paths")
        scope = Path(raw).resolve(strict=False)
        try:
            current.relative_to(scope)
            return True
        except ValueError:
            continue
    return False


def words(value: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", value.lower()))


def is_aios_linear_command(command: str) -> bool:
    # Accept absolute/npm-installed executables while requiring `linear` to be the
    # immediate AIOS subcommand. Separately detected forbidden routes still win.
    return bool(re.search(r"(?:^|[;&|]\s*|\s)(?:[^\s;&|]*/)?aios\s+linear(?:\s|$)", command, re.I))


def classify(event: dict[str, object]) -> str | None:
    tool_name = str(event.get("tool_name", ""))
    operation = str(event.get("operation", "unknown"))
    tool_input = event.get("tool_input", {})
    if not isinstance(tool_input, dict):
        return "tool_input is not an object"

    command = str(tool_input.get("command", ""))
    url = str(tool_input.get("url", ""))
    server = str(tool_input.get("server", ""))
    name = str(tool_input.get("name", ""))
    operation_name = str(tool_input.get("operation_name", ""))
    combined = " ".join((tool_name, server, name, operation_name))
    combined_words = words(combined)

    # Direct Linear API traffic is never the supported route. This catches shell
    # clients and structured HTTP tools without inspecting opaque credentials.
    if "api.linear.app" in command.lower() or "api.linear.app" in url.lower():
        return "direct Linear API access is blocked; use `aios linear`"

    # Old copied wrappers and generic CLIs bypass workspace-local credential and
    # readback policy. Do this check before the allow route so compound shell
    # commands cannot smuggle an additional direct invocation.
    if re.search(r"(?:linear-query|linear-template|(?:^|/)linear\.mjs)(?:\s|$)", command, re.I):
        return "copied Linear scripts are blocked; use `aios linear`"
    stripped = re.sub(r"(?:^|[;&|]\s*|\s)(?:[^\s;&|]*/)?aios\s+linear(?:\s|$)", " ", command, flags=re.I)
    if re.search(r"(?:^|[;&|]\s*|\s)(?:[^\s;&|]*/)?linear(?:\s|$)", stripped, re.I):
        return "generic Linear CLIs are blocked; use `aios linear`"

    if command and is_aios_linear_command(command):
        return None

    # A configured Linear MCP may remain useful for reads, but mutations must use
    # the CLI so all supported runtimes share the same workspace and verification.
    is_linear_tool = "linear" in combined_words or "linear" in combined.lower()
    is_mutation = operation == "mutation" or bool(combined_words & MUTATION_WORDS)
    if is_linear_tool and is_mutation:
        return "Linear MCP mutations are blocked; use `aios linear`"

    return None


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError) as exc:
        return fail(f"malformed JSON payload: {exc}")
    if not isinstance(event, dict) or event.get("event") != "pre_tool":
        return fail("expected a pre_tool event")

    path = config_path()
    if path is None:
        return fail("cannot resolve an absolute XDG config path")
    if not path.exists():
        return 0
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("config root must be an object")
        if not in_guard_scope(str(event.get("cwd", "")), config.get("guardScopes", [])):
            return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        return fail(f"invalid AIOS user config: {exc}")

    reason = classify(event)
    return fail(reason, 2) if reason else 0


if __name__ == "__main__":
    raise SystemExit(main())
