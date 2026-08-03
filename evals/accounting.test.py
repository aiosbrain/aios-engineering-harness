#!/usr/bin/env python3
"""Focused contract tests for observations.v1 accounting."""

from __future__ import annotations

import importlib.util
import json
import re
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
        self.assertEqual(accounting["token_state"], "complete")
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
                        "timestamp": "2026-08-03T00:00:00Z", "formula_method": "token_rate_v1",
                        "inputs": {"token_counts": {"total_tokens": 0, "input_tokens": 100,
                                                       "cached_input_tokens": 0, "output_tokens": 0,
                                                       "reasoning_output_tokens": 0},
                                   "rates_per_token": {"total_tokens": 0, "input_tokens": 0.025,
                                                       "cached_input_tokens": 0, "output_tokens": 0,
                                                       "reasoning_output_tokens": 0}}},
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
                           "attributable_to": "AIO-709", "rule_version": "2026-08",
                           "timestamp": "2026-08-03T00:00:00Z", "method": "proportional_allocation_v1",
                           "inputs": {"subscription_amount": 12, "numerator": 1, "denominator": 4}},
        })
        self.assertEqual(allocation["cost_state"], "allocated_subscription")
        self.assertEqual(allocation["allocation"]["attributable_to"], "AIO-709")

    def test_token_dimensions_are_independent_and_strict(self) -> None:
        total_only = ACCOUNTING.normalize_usage({"tokens": 12})
        self.assertEqual(total_only["token_state"], "partial")
        self.assertEqual(total_only["usage_state"], "reported")
        self.assertEqual(total_only["input_tokens"], None)
        self.assertEqual(total_only["output_tokens"], None)

        cached_only = ACCOUNTING.normalize_usage({"cached_input_tokens": 9})
        self.assertEqual(cached_only["token_state"], "partial")
        self.assertIsNone(cached_only["total_tokens"])

        complete = ACCOUNTING.normalize_usage({
            "total_tokens": 12, "input_tokens": 8, "cached_input_tokens": 4,
            "output_tokens": 4, "reasoning_output_tokens": 2,
        })
        self.assertEqual(complete["token_state"], "complete")
        self.assertEqual(complete["usage_state"], "reported")

        for invalid in (-1, 1.5, float("inf"), float("nan"), True):
            self.assertIsNone(ACCOUNTING.normalize_usage({"tokens": invalid})["total_tokens"])

    def test_pricing_and_allocation_amounts_are_recomputable(self) -> None:
        valid = {
            "cost_amount": 2.5, "cost_currency": "USD", "cost_provenance": "pricing_estimate",
            "pricing": {"catalog_version": "2026-08-01", "model": "gpt-test",
                        "service_tier": "standard", "currency": "USD",
                        "timestamp": "2026-08-03T00:00:00Z", "formula_method": "token_rate_v1",
                        "inputs": {"token_counts": {"total_tokens": 0, "input_tokens": 100,
                                                       "cached_input_tokens": 0, "output_tokens": 0,
                                                       "reasoning_output_tokens": 0},
                                   "rates_per_token": {"total_tokens": 0, "input_tokens": 0.025,
                                                       "cached_input_tokens": 0, "output_tokens": 0,
                                                       "reasoning_output_tokens": 0}}},
        }
        self.assertEqual(ACCOUNTING.normalize_usage(valid)["cost_state"], "pricing_estimate")
        for mutation in (
            {"cost_amount": 2.6},
            {"pricing": {**valid["pricing"], "timestamp": "not-an-iso-time"}},
            {"pricing": {**valid["pricing"], "formula_method": "arbitrary"}},
        ):
            record = {**valid, **mutation}
            self.assertEqual(ACCOUNTING.normalize_usage(record)["cost_state"], "unknown")

        disjoint = {**valid, "cost_amount": 2.13, "pricing": {**valid["pricing"], "inputs": {
            "token_counts": {"total_tokens": 110, "input_tokens": 100, "cached_input_tokens": 20,
                             "output_tokens": 10, "reasoning_output_tokens": 3},
            "rates_per_token": {"total_tokens": 0, "input_tokens": 0.02, "cached_input_tokens": 0.01,
                                "output_tokens": 0.03, "reasoning_output_tokens": 0.04},
        }}}
        self.assertEqual(ACCOUNTING.normalize_usage(disjoint)["cost_state"], "pricing_estimate")
        double_counted = {**disjoint, "pricing": {**disjoint["pricing"], "inputs": {
            **disjoint["pricing"]["inputs"], "rates_per_token": {**disjoint["pricing"]["inputs"]["rates_per_token"], "total_tokens": 0.01},
        }}}
        self.assertEqual(ACCOUNTING.normalize_usage(double_counted)["cost_state"], "unknown")

        runtime = ACCOUNTING.normalize_usage({
            "cost_amount": 1.25, "cost_currency": "USD", "cost_provenance": "runtime_reported",
            "runtime_cost": {"source_field": "result.cost", "semantics": "runtime_reported_not_billed_or_actual"},
        })
        self.assertEqual(runtime["cost_state"], "runtime_reported")
        self.assertEqual(runtime["runtime_cost"]["source_field"], "result.cost")

    def test_verified_outcomes_require_terminal_evidence_and_deduplicate_by_outcome_id(self) -> None:
        sha = "a" * 40
        base = {"program_id": "program", "issue_id": "AIO-709", "phase": "review",
                "attempt_id": "review-1", "run_id": "run-1", "role": "reviewer", "runtime": "codex",
                "model": "gpt-test", "status": "pass", "exit_status": 0, "current_sha": sha,
                "reviewed_sha": sha, "observation_verdict": "pass",
                "usage": {"tokens": 10},
                "verified_outcome": {"outcome_id": "AIO-709:fixed", "verification_id": "review-1",
                    "verifier_role": "reviewer", "terminal_status": "pass", "reviewed_sha": sha,
                    "evidence": [{"basename": "driver.json", "sha256": "b" * 64}]}}
        retry = {**base, "attempt_id": "review-2", "run_id": "run-2",
                 "verified_outcome": {**base["verified_outcome"], "verification_id": "review-2"}}
        aggregate = ACCOUNTING.aggregate_attempts([base, retry])
        self.assertEqual(aggregate["outcome_count"], 1)
        self.assertEqual(aggregate["verified_outcomes"][0]["outcome_id"], "AIO-709:fixed")
        self.assertEqual(aggregate["rollups"]["by_phase"]["review"]["attempt_count"], 2)

        rejected = {**base, "status": "error"}
        self.assertEqual(ACCOUNTING.aggregate_attempts([rejected])["outcome_count"], 0)
        conflict = {**retry, "verified_outcome": {**retry["verified_outcome"], "evidence": [
            {"basename": "driver.json", "sha256": "c" * 64}]}}
        with self.assertRaisesRegex(ValueError, "conflicting verified outcome"):
            ACCOUNTING.aggregate_attempts([base, conflict])

    def test_replay_comparison_includes_terminal_evidence_and_status(self) -> None:
        first = {"program_id": "program", "issue_id": "AIO-709", "phase": "implementation",
                 "attempt_id": "attempt-1", "run_id": "legacy-run", "status": "pass", "exit_status": 0,
                 "current_sha": "a" * 40, "reviewed_sha": "a" * 40, "observation_verdict": "pass",
                 "usage": {"tokens": 10}}
        for field, value in (("status", "error"), ("exit_status", 1), ("current_sha", "b" * 40),
                             ("observation_verdict", "error")):
            changed = {**first, field: value}
            with self.assertRaisesRegex(ValueError, "conflicting duplicate identity"):
                ACCOUNTING.aggregate_attempts([first, changed])

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

    def test_historical_fixtures_retain_sanitized_terminal_evidence_and_conflict_proof(self) -> None:
        for name in ("aio-691.json", "aio-695.json"):
            fixture = json.loads((ROOT / "evals/fixtures/accounting" / name).read_text())
            self.assertEqual(fixture["schema_version"], "accounting-fixture.v2")
            encoded = json.dumps(fixture)
            self.assertNotIn('"transcript"', encoded)
            self.assertNotIn('"final"', encoded)
            self.assertNotIn('"diff"', encoded)
            for attempt in fixture["attempts"]:
                self.assertIn(attempt["status"], {"pass", "unavailable", "error", "fail", "needs_review"})
                self.assertIsInstance(attempt["exit_status"], int)
                self.assertIn(attempt["observation_verdict"], {"pass", "error", "needs_review", "unknown"})
                self.assertTrue(attempt["current_sha"] == "unknown" or re.fullmatch(r"[0-9a-f]{40}", attempt["current_sha"]))
                self.assertTrue(attempt["reviewed_sha"] == "unknown" or re.fullmatch(r"[0-9a-f]{40}", attempt["reviewed_sha"]))
                for source in attempt["source_artifacts"]:
                    self.assertNotIn("/", source["basename"])
                    self.assertRegex(source["sha256"], r"^[0-9a-f]{64}$")

        fixture = json.loads((ROOT / "evals/fixtures/accounting/aio-691.json").read_text())
        self.assertEqual(fixture["retained_conflict_exclusion"]["status"], "error")
        self.assertEqual(fixture["retained_conflict_exclusion"]["observation_verdict"], "error")
        self.assertEqual(fixture["retained_conflict_exclusion"]["source_artifacts"][0]["basename"], "observations.v1.summary.json")
        final = next(record for record in fixture["attempts"] if record.get("verified_outcome"))
        contradictory = {**final, "usage": {**final["usage"], "tokens": final["usage"]["tokens"] + 1}}
        with self.assertRaisesRegex(ValueError, "conflicting duplicate identity"):
            ACCOUNTING.aggregate_attempts([final, contradictory])


if __name__ == "__main__":
    unittest.main()
