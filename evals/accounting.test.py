#!/usr/bin/env python3
"""Focused contract tests for observations.v1 accounting."""

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

ACCOUNTING_SPEC = importlib.util.spec_from_file_location("accounting", ROOT / "evals/lib/accounting.py")
assert ACCOUNTING_SPEC and ACCOUNTING_SPEC.loader
ACCOUNTING = importlib.util.module_from_spec(ACCOUNTING_SPEC)
ACCOUNTING_SPEC.loader.exec_module(ACCOUNTING)


class TerminalAccountingTests(unittest.TestCase):
    def test_terminal_record_preserves_dimensions_and_unknown_cost(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            transcript = root / "transcript.jsonl"
            hooks = root / "hooks.jsonl"
            diff = root / "after.diff"
            transcript.write_text(json.dumps({"type": "turn.completed"}) + "\n")
            hooks.write_text("")
            diff.write_text("")
            observations, summary = OBS.build_observations(
                runtime="codex", transcript_path=transcript, hook_path=hooks,
                driver={"model": "gpt-test", "exit_status": 0, "usage": {
                    "tokens": 125, "input_tokens": 100, "cached_input_tokens": 80,
                    "output_tokens": 25, "reasoning_output_tokens": 15,
                    "cost_usd": None,
                }},
                run_id="run-1", phase="qualification", role="writer", reasoning="high",
                frozen_sha="a" * 40, current_sha="a" * 40, diff_path=diff,
                phase_status="pass",
            )
        terminal = next(row for row in observations if row["event"] == "usage.reported")
        accounting = terminal["summary"]["accounting"]
        self.assertEqual(accounting["total_tokens"], 125)
        self.assertEqual(accounting["input_tokens"], 100)
        self.assertEqual(accounting["cached_input_tokens"], 80)
        self.assertEqual(accounting["output_tokens"], 25)
        self.assertEqual(accounting["reasoning_output_tokens"], 15)
        self.assertEqual(accounting["token_state"], "reported")
        self.assertEqual(accounting["cost_state"], "unknown")
        self.assertEqual(accounting["cost_provenance"], "unknown")
        self.assertIsNone(accounting["cost_usd"])
        self.assertEqual(summary["accounting"]["total_tokens"], 125)
        self.assertEqual(summary["accounting"]["cost_state"], "unknown")

    def test_estimates_and_allocations_require_complete_provenance(self) -> None:
        invalid_estimate = ACCOUNTING.normalize_usage({
            "cost_usd": 2.5, "cost_provenance": "pricing_estimate",
            "pricing": {"catalog_version": "2026-08-01"},
        })
        self.assertEqual(invalid_estimate["cost_state"], "unknown")
        self.assertEqual(invalid_estimate["unclassified_runtime_cost"], {"amount": 2.5, "currency": "USD"})

        estimate = ACCOUNTING.normalize_usage({
            "cost_amount": 2.5, "cost_currency": "USD", "cost_provenance": "pricing_estimate",
            "pricing": {"catalog_version": "2026-08-01", "model": "gpt-test",
                        "service_tier": "standard", "currency": "USD",
                        "timestamp": "2026-08-03T00:00:00Z", "formula": "input*rate"},
        })
        self.assertEqual(estimate["cost_state"], "pricing_estimate")
        self.assertEqual(estimate["pricing"]["catalog_version"], "2026-08-01")

        invalid_allocation = ACCOUNTING.normalize_usage({
            "cost_amount": 3, "cost_currency": "USD", "cost_provenance": "allocated_subscription",
            "allocation": {"allocation_id": "august"},
        })
        self.assertEqual(invalid_allocation["cost_state"], "unknown")

        allocation = ACCOUNTING.normalize_usage({
            "cost_amount": 3, "cost_currency": "EUR", "cost_provenance": "allocated_subscription",
            "allocation": {"allocation_id": "august", "allocation_basis": "active_minutes",
                           "attributable_to": "AIO-709"},
        })
        self.assertEqual(allocation["cost_state"], "allocated_subscription")
        self.assertEqual(allocation["allocation"]["attributable_to"], "AIO-709")

    def test_unknown_propagates_and_legacy_usage_aliases_remain_available(self) -> None:
        unknown = ACCOUNTING.normalize_usage({"tokens": None, "cost_usd": None})
        self.assertEqual(unknown["token_state"], "unknown")
        self.assertEqual(unknown["cost_state"], "unknown")
        self.assertIsNone(unknown["total_tokens"])
        self.assertIsNone(unknown["tokens"])
        self.assertIsNone(unknown["cost_usd"])

        legacy = ACCOUNTING.normalize_usage({"tokens": 12, "cost_usd": 0.75})
        self.assertEqual(legacy["tokens"], 12)
        self.assertEqual(legacy["total_tokens"], 12)
        self.assertEqual(legacy["cost_state"], "unknown")
        self.assertEqual(legacy["unclassified_runtime_cost"], {"amount": 0.75, "currency": "USD"})

        currencies = ACCOUNTING.aggregate_attempts([
            {"attempt_id": "usd", "usage": {"cost_usd": 1}},
            {"attempt_id": "eur", "usage": {"cost_amount": 2, "cost_currency": "EUR"}},
        ])["costs"]
        self.assertEqual(currencies["unclassified_runtime"], {"USD": 1, "EUR": 2})

    def test_retries_are_visible_replays_deduplicate_and_conflicts_fail_closed(self) -> None:
        first = {"program_id": "program", "issue_id": "AIO-709", "phase": "implementation",
                 "attempt_id": "attempt-1", "run_id": "run-1", "role": "writer", "runtime": "codex",
                 "model": "gpt-test", "usage": ACCOUNTING.normalize_usage({"tokens": 10})}
        retry = {**first, "attempt_id": "attempt-2", "run_id": "run-2",
                 "usage": ACCOUNTING.normalize_usage({"tokens": 20})}
        aggregate = ACCOUNTING.aggregate_attempts([first, retry, first])
        self.assertEqual(aggregate["attempt_count"], 2)
        self.assertEqual(aggregate["deduplicated_replays"], 1)
        self.assertEqual(aggregate["tokens"]["total_tokens"], 30)
        self.assertEqual([attempt["attempt_id"] for attempt in aggregate["attempts"]], ["attempt-1", "attempt-2"])

        conflict = {**first, "usage": ACCOUNTING.normalize_usage({"tokens": 11})}
        with self.assertRaisesRegex(ValueError, "conflicting duplicate identity"):
            ACCOUNTING.aggregate_attempts([first, conflict])

    def test_sanitized_aio_695_replay_is_exact_once_and_cost_unknown(self) -> None:
        records = json.loads((ROOT / "evals/fixtures/accounting/aio-695.json").read_text())["attempts"]
        aggregate = ACCOUNTING.aggregate_attempts(records + records)
        self.assertEqual(aggregate["attempt_count"], 6)
        self.assertEqual(aggregate["deduplicated_replays"], 6)
        self.assertIsNone(aggregate["tokens"]["total_tokens"])
        self.assertEqual(aggregate["tokens"]["known_total_tokens"], 7_085_001)
        self.assertEqual(aggregate["tokens"]["unknown_attempts"], 1)
        self.assertEqual(aggregate["costs"], {"runtime_reported": {}, "pricing_estimate": {},
                                               "allocated_subscription": {}, "unclassified_runtime": {},
                                               "unknown_attempts": 6})

    def test_sanitized_aio_691_retains_retries_and_one_verified_outcome(self) -> None:
        fixture = json.loads((ROOT / "evals/fixtures/accounting/aio-691.json").read_text())
        aggregate = ACCOUNTING.aggregate_attempts(fixture["attempts"])
        self.assertEqual(aggregate["attempt_count"], fixture["successful_chain_attempt_count"])
        self.assertIsNone(aggregate["tokens"]["total_tokens"])
        self.assertEqual(aggregate["tokens"]["known_total_tokens"], fixture["successful_chain_total_tokens"])
        self.assertEqual(aggregate["outcome_count"], 1)


if __name__ == "__main__":
    unittest.main()
