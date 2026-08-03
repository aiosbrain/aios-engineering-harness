#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "evals/lib/build_observations.py"
SPEC = importlib.util.spec_from_file_location("build_observations", SCRIPT)
assert SPEC and SPEC.loader
OBS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(OBS)


class ObservationTests(unittest.TestCase):
    def build(self, transcript: list[str], hooks: list[str] | None = None,
              driver: dict | None = None, phase_status: str = "pass") -> tuple[list[dict], dict]:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            transcript_path = root / "transcript.jsonl"
            hooks_path = root / "hook-events.jsonl"
            diff_path = root / "after.diff"
            transcript_path.write_text("\n".join(transcript) + "\n")
            hooks_path.write_text("\n".join(hooks or []) + ("\n" if hooks else ""))
            diff_path.write_text("diff --git a/a b/a\n+safe summary\n")
            values = OBS.build_observations(
                runtime="codex", transcript_path=transcript_path, hook_path=hooks_path,
                driver=driver or {"model": "gpt-test", "exit_status": 0,
                                  "usage": {"tokens": 12, "cost_usd": None}},
                run_id="run-1", phase="qualification", role="writer", reasoning="high",
                frozen_sha="a" * 40, current_sha="b" * 40, diff_path=diff_path,
                phase_status=phase_status,
            )
            return values

    def test_complete_lifecycle_and_binding_pass(self) -> None:
        transcript = [
            json.dumps({"type": "thread.started", "thread_id": "thread-1"}),
            json.dumps({"type": "turn.started"}),
            json.dumps({"type": "item.started", "item": {"id": "tool-1", "type": "command_execution", "command": "node --test test/a.test.mjs"}}),
            json.dumps({"type": "item.completed", "item": {"id": "tool-1", "type": "command_execution", "command": "node --test test/a.test.mjs", "exit_code": 0}}),
            json.dumps({"type": "turn.completed", "usage": {"input_tokens": 8, "output_tokens": 4}}),
        ]
        hooks = [json.dumps({"event": "session_start", "tool_id": "", "trace": {"policy": "inject-context.sh", "outcome": 0}})]
        observations, summary = self.build(transcript, hooks)
        self.assertEqual(summary["verdict"], "pass")
        self.assertEqual([row["sequence"] for row in observations], list(range(1, len(observations) + 1)))
        self.assertTrue(all(row["frozen_sha"] == "a" * 40 and row["current_sha"] == "b" * 40 for row in observations))
        self.assertTrue(all(row["turn_id"] is not None or row["item_id"] is not None for row in observations))
        self.assertTrue(all(row["diff_hash"].startswith("sha256:") for row in observations))
        self.assertTrue(all("safe summary" not in json.dumps(row) for row in observations))
        self.assertTrue(any(row["event"] == "check.completed" and row["status"] == "pass" for row in observations))

    def test_started_tool_without_terminal_is_harness_error(self) -> None:
        transcript = [
            json.dumps({"type": "turn.started"}),
            json.dumps({"type": "item.started", "item": {"id": "tool-1", "type": "command_execution", "command": "node --test test/a.test.mjs"}}),
        ]
        observations, summary = self.build(transcript, [json.dumps({"event": "session_start", "trace": {"policy": "inject-context.sh", "outcome": 0}})])
        self.assertEqual(summary["verdict"], "error")
        incomplete = [row for row in observations if row["event"] == "telemetry.incomplete"]
        self.assertTrue(incomplete)
        self.assertTrue(all(row["attribution"] == "harness" for row in incomplete))

    def test_missing_hooks_and_malformed_jsonl_never_pass(self) -> None:
        transcript = ["{malformed", json.dumps({"type": "turn.started"}), json.dumps({"type": "turn.completed", "usage": {}})]
        observations, summary = self.build(transcript)
        self.assertEqual(summary["verdict"], "error")
        self.assertTrue(any(row["event"] == "telemetry.malformed" for row in observations))
        self.assertTrue(any(row["event"] == "telemetry.incomplete" and row["attribution"] == "harness" for row in observations))

    def test_provider_failure_before_actionable_output_is_runtime_environment(self) -> None:
        transcript = [json.dumps({"type": "thread.started", "thread_id": "thread-1"}),
                      json.dumps({"type": "item.completed", "item": {"id": "err-1", "type": "error"}})]
        observations, summary = self.build(transcript, driver={"model": "gpt-test", "exit_status": 127,
                                                               "usage": {"tokens": None, "cost_usd": None}},
                                                   phase_status="unavailable")
        failures = [row for row in observations if row["event"] == "provider.failure"]
        self.assertTrue(failures)
        self.assertEqual(failures[0]["attribution"], "runtime_environment")
        self.assertEqual(summary["usage_state"], "unknown")

    def test_masked_pipeline_is_model_attributed_needs_review(self) -> None:
        transcript = [
            json.dumps({"type": "turn.started"}),
            json.dumps({"type": "item.started", "item": {"id": "tool-1", "type": "command_execution", "command": "node --test test/a.test.mjs | sed -n 1,20p"}}),
            json.dumps({"type": "item.completed", "item": {"id": "tool-1", "type": "command_execution", "command": "node --test test/a.test.mjs | sed -n 1,20p", "exit_code": 0}}),
            json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}}),
        ]
        hooks = [json.dumps({"event": "session_start", "trace": {"policy": "inject-context.sh", "outcome": 0}})]
        observations, summary = self.build(transcript, hooks)
        unsafe = [row for row in observations if row["event"] == "check.completed"]
        self.assertEqual(unsafe[0]["status"], "needs_review")
        self.assertEqual(unsafe[0]["attribution"], "model")
        self.assertEqual(summary["verdict"], "needs_review")

    def test_duplicate_hook_decisions_are_harness_errors(self) -> None:
        transcript = [json.dumps({"type": "turn.started"}),
                      json.dumps({"type": "turn.completed", "usage": {"input_tokens": 1, "output_tokens": 1}})]
        hook = json.dumps({"event": "session_start", "tool_id": "", "trace": {"policy": "inject-context.sh", "outcome": 0}})
        observations, summary = self.build(transcript, [hook, hook])
        self.assertEqual(summary["verdict"], "error")
        self.assertTrue(any(row["event"] == "telemetry.contradictory" and row["attribution"] == "harness"
                            for row in observations))


if __name__ == "__main__":
    unittest.main()
