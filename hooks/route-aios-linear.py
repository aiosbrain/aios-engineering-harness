#!/usr/bin/env python3
"""Inject the portable AIOS Linear skill for scoped Linear prompts."""

from __future__ import annotations

import json
import os
from pathlib import Path
import re
import sys


PROMPT_CAP = 32768
POINTER_CAP = 2048
MARKER = "<!-- aios-skill-route:aios-linear -->"


def config_path() -> Path | None:
    xdg = os.environ.get("XDG_CONFIG_HOME", "").strip()
    if xdg:
        root = Path(xdg)
        return root / "aios" / "config.json" if root.is_absolute() else None
    home = os.environ.get("HOME", "").strip()
    return Path(home) / ".config" / "aios" / "config.json" if home else None


def scoped(cwd: str, scopes: object) -> bool:
    if not isinstance(scopes, list):
        raise ValueError("guardScopes must be an array")
    current = Path(cwd).resolve(strict=False)
    for raw in scopes:
        if not isinstance(raw, str) or not raw or not Path(raw).is_absolute():
            raise ValueError("guardScopes entries must be absolute paths")
        try:
            current.relative_to(Path(raw).resolve(strict=False))
            return True
        except ValueError:
            continue
    return False


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, OSError) as exc:
        print(f"route-aios-linear: malformed JSON payload: {exc}", file=sys.stderr)
        return 3
    if not isinstance(event, dict) or event.get("event") != "user_prompt_submit":
        print("route-aios-linear: expected a user_prompt_submit event", file=sys.stderr)
        return 3
    prompt = event.get("prompt", "")
    if not isinstance(prompt, str) or len(prompt.encode("utf-8")) > PROMPT_CAP:
        return 0
    if MARKER in prompt or not re.search(r"\blinear\b|\bissue tracker\b", prompt, re.I):
        return 0

    path = config_path()
    if path is None:
        print("route-aios-linear: cannot resolve an absolute XDG config path", file=sys.stderr)
        return 3
    if not path.exists():
        return 0
    try:
        config = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(config, dict):
            raise ValueError("config root must be an object")
        if not scoped(str(event.get("cwd", "")), config.get("guardScopes", [])):
            return 0
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"route-aios-linear: invalid AIOS user config: {exc}", file=sys.stderr)
        return 3

    root = Path(__file__).resolve().parent.parent
    skill = root / "skills" / "aios-linear" / "SKILL.md"
    if not skill.is_file():
        print(f"route-aios-linear: missing installed skill: {skill}", file=sys.stderr)
        return 3
    text = (
        f"Linear task in an AIOS guard scope: read {skill} in full before acting, "
        f"then use the workspace-bound `aios linear` CLI route. {MARKER}"
    )
    if len(text.encode("utf-8")) > POINTER_CAP:
        return 0
    json.dump({"protocol": "1.1", "action": "context", "text": text}, sys.stdout)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
