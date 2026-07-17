#!/usr/bin/env python3
"""Convert supported runtime JSONL transcripts to normalized eval evidence."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any


def relative(path: str, workspace: str) -> str:
    try:
        return os.path.relpath(path, workspace) if os.path.isabs(path) else path
    except ValueError:
        return path


def event_base(runtime: str, kind: str, workspace: str, session: str = "") -> dict[str, Any]:
    return {
        "protocol_version": "1.0",
        "event": kind,
        "runtime": {"name": runtime},
        "cwd": workspace,
        "session_id": session,
    }


def is_check(command: str) -> bool:
    return "check.py" in command or "unittest" in command


def patch_paths(patch: str, workspace: str) -> list[dict[str, str]]:
    changes: list[dict[str, str]] = []
    current = ""
    for line in patch.splitlines():
        for marker, action in (("*** Add File: ", "add"), ("*** Update File: ", "update"), ("*** Delete File: ", "delete")):
            if line.startswith(marker):
                current = line[len(marker):]
                changes.append({"path": relative(current, workspace), "action": action})
                break
        if line.startswith("*** Move to: ") and changes:
            destination = line[len("*** Move to: "):]
            source = current
            current = destination
            changes[-1] = {"path": relative(destination, workspace), "action": "rename", "from": relative(source, workspace)}
    return changes


def codex(record: dict[str, Any], workspace: str) -> list[dict[str, Any]]:
    if record.get("type") != "item.completed":
        return []
    item = record.get("item") or {}
    if item.get("type") == "file_change":
        changes = []
        for change in item.get("changes") or []:
            action = change.get("kind", "unknown")
            if action not in {"add", "update", "delete", "rename"}:
                action = "unknown"
            changes.append({"path": relative(change.get("path", ""), workspace), "action": action})
        if not changes:
            return []
        out = event_base("codex", "pre_edit", workspace)
        out.update({"tool_name": "apply_patch", "tool_id": item.get("id", ""), "paths": changes, "added_content": []})
        return [out]
    if item.get("type") == "command_execution":
        command = item.get("command") or ""
        if not command:
            return []
        out = event_base("codex", "pre_command", workspace)
        out.update({"tool_name": "Bash", "tool_id": item.get("id", ""), "command": command})
        records = [out]
        if is_check(command):
            records.append({"record_type": "check", "command": command, "status": item.get("exit_code", 1)})
        return records
    return []


def claude(record: dict[str, Any], workspace: str, pending: dict[str, str]) -> list[dict[str, Any]]:
    message = record.get("message") or {}
    content = message.get("content") or []
    records: list[dict[str, Any]] = []
    if record.get("type") == "assistant":
        for part in content:
            if part.get("type") != "tool_use":
                continue
            name = part.get("name", "")
            tool_id = part.get("id", "")
            args = part.get("input") or {}
            if name in {"Write", "Edit", "MultiEdit"}:
                path = args.get("file_path") or args.get("path") or ""
                out = event_base("claude", "pre_edit", workspace, record.get("session_id", ""))
                out.update({"tool_name": name, "tool_id": tool_id,
                            "paths": [{"path": relative(path, workspace), "action": "add" if name == "Write" else "update"}],
                            "added_content": [{"path": relative(path, workspace), "content": args.get("content") or args.get("new_string") or ""}]})
                records.append(out)
            elif name == "Bash":
                command = args.get("command") or ""
                pending[tool_id] = command
                out = event_base("claude", "pre_command", workspace, record.get("session_id", ""))
                out.update({"tool_name": name, "tool_id": tool_id, "command": command})
                records.append(out)
    elif record.get("type") == "user":
        for part in content:
            if part.get("type") != "tool_result":
                continue
            tool_id = part.get("tool_use_id", "")
            command = pending.pop(tool_id, "")
            if is_check(command):
                text = json.dumps(part.get("content", ""))
                failed = bool(part.get("is_error")) or "FAILED" in text or "exit code 1" in text
                records.append({"record_type": "check", "command": command, "status": 1 if failed else 0})
    return records


def opencode(record: dict[str, Any], workspace: str) -> list[dict[str, Any]]:
    part = record.get("part") or record.get("properties") or {}
    if part.get("type") != "tool":
        return []
    tool = part.get("tool") or part.get("name") or ""
    state = part.get("state") or {}
    args = state.get("input") or part.get("input") or {}
    tool_id = part.get("callID") or part.get("id") or ""
    if tool in {"write", "edit", "apply_patch", "patch"}:
        patch = args.get("patchText") or args.get("patch") or ""
        changes = patch_paths(patch, workspace) if patch else []
        path = args.get("filePath") or args.get("file_path") or args.get("path") or "<patch>"
        if not changes:
            changes = [{"path": relative(path, workspace), "action": "add" if tool == "write" else "update"}]
        out = event_base("opencode", "pre_edit", workspace, record.get("sessionID", ""))
        out.update({"tool_name": tool, "tool_id": tool_id,
                    "paths": changes,
                    "added_content": []})
        return [out]
    if tool == "bash":
        command = args.get("command") or ""
        out = event_base("opencode", "pre_command", workspace, record.get("sessionID", ""))
        out.update({"tool_name": tool, "tool_id": tool_id, "command": command})
        records = [out]
        if is_check(command) and state.get("status") in {"completed", "error"}:
            output = str(state.get("output") or state.get("error") or "")
            failed = state.get("status") == "error" or "FAILED" in output
            records.append({"record_type": "check", "command": command, "status": 1 if failed else 0})
        return records
    return []


def main() -> int:
    if len(sys.argv) != 5:
        return 2
    runtime, transcript, output, workspace = sys.argv[1:]
    pending: dict[str, str] = {}
    count = 0
    with open(output, "w", encoding="utf-8") as target:
        try:
            lines = Path(transcript).read_text(errors="replace").splitlines()
        except OSError:
            return 0
        for line in lines:
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if runtime == "codex":
                events = codex(record, workspace)
            elif runtime == "claude":
                events = claude(record, workspace, pending)
            elif runtime == "opencode":
                events = opencode(record, workspace)
            else:
                events = []
            for event in events:
                target.write(json.dumps(event, separators=(",", ":")) + "\n")
                count += 1
    return 0 if count else 4


if __name__ == "__main__":
    raise SystemExit(main())
