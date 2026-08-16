#!/usr/bin/env python3
"""Build sanitized, fail-closed observations.v1 JSONL from eval artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
import normalize_transcript
import accounting


TOOL_TYPES = {"command_execution", "file_change", "mcp_tool_call", "collab_tool_call"}
ATTRIBUTIONS = {"model", "harness", "runtime_environment", "product", "unknown"}


def hash_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def file_hash(path: Path) -> str:
    try:
        return hash_bytes(path.read_bytes())
    except OSError:
        return hash_bytes(b"")


def artifact_ref(path: Path) -> str:
    return f"{path.name}#{file_hash(path)}"


def json_hash(value: Any) -> str:
    return hash_bytes(json.dumps(value, sort_keys=True, separators=(",", ":")).encode())


def read_jsonl(path: Path) -> tuple[list[dict[str, Any]], int]:
    records: list[dict[str, Any]] = []
    malformed = 0
    try:
        lines = path.read_text(errors="replace").splitlines()
    except OSError:
        return records, 1
    for line in lines:
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            malformed += 1
            continue
        if isinstance(value, dict):
            records.append(value)
        else:
            malformed += 1
    return records, malformed


def build_observations(
    *, runtime: str, transcript_path: Path, hook_path: Path, driver: dict[str, Any],
    run_id: str, phase: str, role: str, reasoning: str, frozen_sha: str,
    current_sha: str, diff_path: Path, phase_status: str, program_id: str = "unknown",
    issue_id: str = "unknown", attempt_id: str | None = None,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    transcript, malformed_transcript = read_jsonl(transcript_path)
    hooks, malformed_hooks = read_jsonl(hook_path)
    model = str(driver.get("model") or "unknown")
    runtime_version = str(driver.get("cli_version") or "unknown")
    harness_sha = str(driver.get("harness_sha") or "unknown")
    diff_hash = file_hash(diff_path)
    transcript_ref = artifact_ref(transcript_path)
    hook_ref = artifact_ref(hook_path)
    driver_ref = "driver.json#" + json_hash(driver)
    observations: list[dict[str, Any]] = []
    issues: list[tuple[str, str, str]] = []
    sequence = 0
    turn_number = 0
    current_turn = ""
    started_turns: list[str] = []
    completed_turns: set[str] = set()
    started_tools: dict[str, str] = {}
    completed_tools: set[str] = set()
    started_checks: set[str] = set()
    completed_checks: set[str] = set()
    thread_id = ""
    valid_model_output = False
    error_items: list[str] = []

    def emit(event: str, status: str, source: str, severity: str, attribution: str,
             *, turn_id: str | None = None, item_id: str | None = None,
             summary: dict[str, Any] | None = None) -> None:
        nonlocal sequence
        sequence += 1
        if attribution not in ATTRIBUTIONS:
            attribution = "unknown"
        if turn_id is None and item_id is None:
            turn_id = current_turn or f"{run_id}:run"
        observations.append({
            "schema_version": "observations.v1", "program_id": program_id, "issue_id": issue_id,
            "attempt_id": attempt_id or run_id, "run_id": run_id, "phase": phase,
            "role": role, "runtime": runtime, "model": model,
            "runtime_version": runtime_version, "harness_sha": harness_sha,
            "reasoning_level": reasoning, "turn_id": turn_id,
            "item_id": item_id, "sequence": sequence, "frozen_sha": frozen_sha,
            "current_sha": current_sha, "diff_hash": diff_hash, "event": event,
            "status": status, "source_artifact": source, "severity": severity,
            "attribution": attribution, "summary": summary or {},
        })

    for record in transcript:
        kind = record.get("type")
        if kind == "thread.started":
            thread_id = str(record.get("thread_id") or "thread-unknown")
            emit("run.started", "started", transcript_ref, "info", "unknown",
                 summary={"thread_id_hash": hash_bytes(thread_id.encode())})
            continue
        if kind == "turn.started":
            turn_number += 1
            current_turn = f"{thread_id or run_id}:turn-{turn_number}"
            started_turns.append(current_turn)
            emit("turn.started", "started", transcript_ref, "info", "unknown", turn_id=current_turn)
            continue
        if kind == "turn.completed":
            terminal_turn = current_turn or f"{thread_id or run_id}:turn-{max(turn_number, 1)}"
            if terminal_turn in completed_turns or terminal_turn not in started_turns:
                issues.append(("error", "harness", "turn lifecycle contradiction"))
                emit("telemetry.contradictory", "error", transcript_ref, "error", "harness",
                     turn_id=terminal_turn, summary={"lifecycle": "turn"})
            completed_turns.add(terminal_turn)
            usage = record.get("usage") if isinstance(record.get("usage"), dict) else {}
            emit("turn.completed", "pass", transcript_ref, "info", "unknown",
                 turn_id=terminal_turn,
                 summary={"usage": {key: usage.get(key) if isinstance(usage.get(key), (int, float)) else None
                                    for key in ("input_tokens", "cached_input_tokens", "cache_creation_input_tokens",
                                                "output_tokens", "reasoning_output_tokens")}})
            continue
        if kind not in {"item.started", "item.completed"}:
            continue
        item = record.get("item") if isinstance(record.get("item"), dict) else {}
        item_id = str(item.get("id") or "")
        item_type = str(item.get("type") or "unknown")
        if item_type == "agent_message" and kind == "item.completed":
            valid_model_output = True
        if item_type == "error" and kind == "item.completed":
            error_items.append(item_id)
            continue
        if item_type not in TOOL_TYPES:
            continue
        if kind == "item.started":
            if not item_id or item_id in started_tools:
                issues.append(("error", "harness", "tool start is missing an id or duplicated"))
                emit("telemetry.contradictory", "error", transcript_ref, "error", "harness",
                     turn_id=current_turn or None, item_id=item_id or None,
                     summary={"lifecycle": "tool_start"})
                continue
            started_tools[item_id] = item_type
            valid_model_output = True
            emit("tool.started", "started", transcript_ref, "info", "unknown",
                 turn_id=current_turn or None, item_id=item_id, summary={"tool_type": item_type})
            command = str(item.get("command") or "")
            if item_type == "command_execution" and normalize_transcript.is_check(command):
                started_checks.add(item_id)
                emit("check.started", "started", transcript_ref, "info", "unknown",
                     turn_id=current_turn or None, item_id=item_id,
                     summary={"check_kind": normalize_transcript.check_kind(command),
                              "command_hash": hash_bytes(command.encode())})
            continue

        if item_id in completed_tools:
            issues.append(("error", "harness", "duplicate tool terminal"))
            emit("telemetry.contradictory", "error", transcript_ref, "error", "harness",
                 turn_id=current_turn or None, item_id=item_id or None,
                 summary={"lifecycle": "tool_terminal"})
            continue
        if not item_id or item_id not in started_tools:
            issues.append(("needs_review", "harness", "tool terminal without observed start"))
            emit("telemetry.contradictory", "needs_review", transcript_ref, "warning", "harness",
                 turn_id=current_turn or None, item_id=item_id or None,
                 summary={"lifecycle": "tool_terminal_without_start"})
        completed_tools.add(item_id)
        exit_code = item.get("exit_code")
        numeric_exit = isinstance(exit_code, (int, float)) and not isinstance(exit_code, bool)
        tool_status = "pass" if item_type != "command_execution" or (numeric_exit and exit_code == 0) else "fail"
        if item_type == "command_execution" and not numeric_exit:
            tool_status = "error"
            issues.append(("error", "harness", "completed command has no authoritative exit code"))
        emit("tool.completed", tool_status, transcript_ref,
             "error" if tool_status == "error" else "info",
             "harness" if tool_status == "error" else "unknown",
             turn_id=current_turn or None, item_id=item_id or None,
             summary={"tool_type": item_type, "exit_code": exit_code if numeric_exit else None})
        if item_type == "file_change":
            changes = item.get("changes") if isinstance(item.get("changes"), list) else []
            sanitized = [{"action": str(change.get("kind") or "unknown"),
                          "path_hash": hash_bytes(str(change.get("path") or "").encode())}
                         for change in changes if isinstance(change, dict)]
            emit("edit.completed", "pass", transcript_ref, "info", "model",
                 turn_id=current_turn or None, item_id=item_id or None,
                 summary={"change_count": len(sanitized), "changes": sanitized})
        if item_type == "command_execution":
            command = str(item.get("command") or "")
            check_kind = normalize_transcript.check_kind(command)
            if check_kind:
                if item_id not in started_checks:
                    issues.append(("needs_review", "harness", "check terminal without observed start"))
                completed_checks.add(item_id)
                unsafe = normalize_transcript.masked_pipeline(command)
                check_status = "needs_review" if unsafe else ("pass" if numeric_exit and exit_code == 0 else "fail")
                if unsafe:
                    issues.append(("needs_review", "model", "test command used an unguarded pipeline"))
                emit("check.completed", check_status, transcript_ref,
                     "error" if unsafe else "info", "model" if unsafe else "unknown",
                     turn_id=current_turn or None, item_id=item_id or None,
                     summary={"check_kind": check_kind, "exit_code": exit_code if numeric_exit else None,
                              "command_hash": hash_bytes(command.encode()), "pipefail_proven": not unsafe})

    session_hook_seen = False
    external_check_index = 0
    seen_hook_decisions: set[tuple[str, str, str, str]] = set()
    for hook in hooks:
        trace = hook.get("trace") if isinstance(hook.get("trace"), dict) else None
        if hook.get("event") == "session_start" and trace:
            session_hook_seen = True
        if trace:
            outcome = trace.get("outcome")
            policy = str(trace.get("policy") or "unknown")
            decision_key = (str(hook.get("event") or "unknown"), policy,
                            str(hook.get("tool_id") or ""), str(outcome))
            if decision_key in seen_hook_decisions:
                issues.append(("error", "harness", "duplicate hook decision"))
                emit("telemetry.contradictory", "error", hook_ref, "error", "harness",
                     item_id=str(hook.get("tool_id") or "") or None,
                     summary={"lifecycle": "duplicate_hook_decision", "policy": policy})
            seen_hook_decisions.add(decision_key)
            status = "pass" if outcome == 0 else ("fail" if outcome == 2 else "error")
            attribution = "model" if outcome == 2 else ("harness" if status == "error" else "unknown")
            if status == "error":
                issues.append(("error", "harness", "hook policy could not be evaluated"))
            emit("guard.decision", status, hook_ref, "error" if status != "pass" else "info", attribution,
                 item_id=str(hook.get("tool_id") or "") or None,
                 summary={"event": str(hook.get("event") or "unknown"), "policy": policy,
                          "outcome": outcome if isinstance(outcome, (int, float)) else None})
        if hook.get("record_type") == "check":
            external_check_index += 1
            status = hook.get("status")
            numeric = isinstance(status, (int, float)) and not isinstance(status, bool)
            command = str(hook.get("command") or "")
            emit("check.completed", "pass" if numeric and status == 0 else "fail", hook_ref, "info", "product",
                 item_id=f"external-check-{external_check_index}",
                 summary={"check_kind": normalize_transcript.check_kind(command),
                          "exit_code": status if numeric else None, "command_hash": hash_bytes(command.encode()),
                          "execution_owner": "harness"})

    for turn_id in started_turns:
        if turn_id not in completed_turns:
            issues.append(("error", "harness", "started turn has no terminal event"))
            emit("telemetry.incomplete", "error", transcript_ref, "error", "harness",
                 turn_id=turn_id, summary={"lifecycle": "turn"})
    for item_id, item_type in started_tools.items():
        if item_id not in completed_tools:
            issues.append(("error", "harness", "started tool has no terminal event"))
            emit("telemetry.incomplete", "error", transcript_ref, "error", "harness",
                 item_id=item_id, summary={"lifecycle": "tool", "tool_type": item_type})
    for item_id in started_checks:
        if item_id not in completed_checks:
            issues.append(("error", "harness", "started check has no terminal event"))
            emit("telemetry.incomplete", "error", transcript_ref, "error", "harness",
                 item_id=item_id, summary={"lifecycle": "check"})
    if malformed_transcript or malformed_hooks:
        issues.append(("error", "harness", "malformed telemetry"))
        emit("telemetry.malformed", "error", transcript_ref if malformed_transcript else hook_ref,
             "error", "harness", summary={"transcript_lines": malformed_transcript, "hook_lines": malformed_hooks})
    if runtime == "codex" and not session_hook_seen:
        issues.append(("error", "harness", "required headless session hook was not observed"))
        emit("telemetry.incomplete", "error", hook_ref, "error", "harness",
             summary={"lifecycle": "required_session_hook"})

    driver_exit = driver.get("exit_status")
    for item_id in error_items:
        recovered = driver_exit in {0, 0.0} and bool(completed_turns)
        emit("runtime.diagnostic" if recovered else "provider.error_item",
             "recovered" if recovered else "error", transcript_ref,
             "warning" if recovered else "error", "runtime_environment",
             item_id=item_id or None, summary={"item_type": "error"})
    if driver_exit not in {0, 0.0}:
        attribution = "runtime_environment" if not valid_model_output else "runtime_environment"
        emit("provider.failure", "error", driver_ref, "error", attribution,
             summary={"exit_status": driver_exit if isinstance(driver_exit, (int, float)) else None,
                      "actionable_model_output": valid_model_output})

    usage = accounting.normalize_usage(driver.get("usage"))
    usage_state = usage["usage_state"]
    emit("usage.reported", usage["token_state"], driver_ref, "info", "runtime_environment",
         summary={"tokens": usage["tokens"], "cost_usd": usage["cost_usd"],
                  "token_state": usage["token_state"], "cost_state": usage["cost_state"],
                  "cost_provenance": usage["cost_provenance"], "accounting": usage})

    issue_levels = {level for level, _, _ in issues}
    verdict = "error" if "error" in issue_levels else ("needs_review" if "needs_review" in issue_levels else "pass")
    effective_status = phase_status
    if phase_status in {"pass", "needs_review"}:
        effective_status = verdict if verdict != "pass" else phase_status
    gate_attribution = "unknown"
    if effective_status == "error":
        gate_attribution = next((attr for level, attr, _ in issues if level == "error"), "harness")
    elif effective_status == "needs_review":
        gate_attribution = next((attr for level, attr, _ in issues if level == "needs_review"), "unknown")
    elif effective_status in {"unavailable", "timeout"}:
        gate_attribution = "runtime_environment"
    elif effective_status == "fail":
        gate_attribution = "model" if valid_model_output else "product"
    emit("phase.gate", effective_status, driver_ref,
         "info" if effective_status == "pass" else "error", gate_attribution,
         summary={"observation_verdict": verdict, "issue_count": len(issues)})

    summary = {
        "schema_version": "observations.v1", "program_id": program_id, "issue_id": issue_id,
        "attempt_id": attempt_id or run_id, "run_id": run_id, "phase": phase, "role": role,
        "verdict": verdict,
        "effective_status": effective_status, "observation_count": len(observations),
        "malformed_transcript_lines": malformed_transcript, "malformed_hook_lines": malformed_hooks,
        "started_turns": len(started_turns), "completed_turns": len(completed_turns),
        "started_tools": len(started_tools), "completed_tools": len(completed_tools),
        "started_checks": len(started_checks), "completed_checks": len(completed_checks),
        "headless_session_hook_seen": session_hook_seen, "usage_state": usage_state,
        "accounting": usage,
        "issues": [{"severity": level, "attribution": attribution, "summary": summary}
                   for level, attribution, summary in issues],
    }
    return observations, summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--transcript", type=Path, required=True)
    parser.add_argument("--hooks", type=Path, required=True)
    parser.add_argument("--driver", type=Path, required=True)
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--phase", required=True)
    parser.add_argument("--role", required=True)
    parser.add_argument("--reasoning", required=True)
    parser.add_argument("--frozen-sha", required=True)
    parser.add_argument("--current-sha", required=True)
    parser.add_argument("--diff", type=Path, required=True)
    parser.add_argument("--phase-status", required=True)
    parser.add_argument("--program-id", default="unknown")
    parser.add_argument("--issue-id", default="unknown")
    parser.add_argument("--attempt-id")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    args = parser.parse_args()
    try:
        driver = json.loads(args.driver.read_text())
    except (OSError, json.JSONDecodeError):
        driver = {"model": "unknown", "exit_status": None, "usage": {"tokens": None, "cost_usd": None}}
    observations, summary = build_observations(
        runtime=args.runtime, transcript_path=args.transcript, hook_path=args.hooks,
        driver=driver, run_id=args.run_id, phase=args.phase, role=args.role,
        reasoning=args.reasoning, frozen_sha=args.frozen_sha, current_sha=args.current_sha,
        diff_path=args.diff, phase_status=args.phase_status, program_id=args.program_id,
        issue_id=args.issue_id, attempt_id=args.attempt_id,
    )
    args.output.write_text("".join(json.dumps(row, separators=(",", ":"), allow_nan=False) + "\n" for row in observations))
    args.summary.write_text(json.dumps(summary, separators=(",", ":"), allow_nan=False) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
