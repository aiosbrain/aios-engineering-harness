#!/usr/bin/env python3
"""Producer tests for the sanitized finding-candidate inventory boundary."""
import importlib.util
import json
import sys
import tempfile
import unittest
from types import SimpleNamespace
from unittest import mock
from pathlib import Path

ROOT = Path(__file__).parent
MODULE_PATH = ROOT / "lib/build_finding_observations.py"
SPEC = importlib.util.spec_from_file_location("finding_producer", MODULE_PATH)
PRODUCER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRODUCER)
CONFIG = ROOT / "config/finding-observations.trusted.json"
SCHEMA = ROOT / "schemas/finding-observations.v1.schema.json"
OBSERVED_AT = "2026-09-08T00:00:00Z"
KEY = {"kind": "structural_sha256", "value": "1" * 64}
try:
    import jsonschema  # noqa: F401 - development-only conformance dependency
    sys.path.insert(0, str(ROOT))
    from finding_observations_test_support import read_jsonl, validate
except ImportError:
    print("SKIPPED: finding producer tests require development-only jsonschema", file=sys.stderr)
    sys.exit(77)


def candidate(key=None, outcome="verified", evidence="complete"):
    if key is None:
        key = KEY
    return {
        "source_record_key": key,
        "codebases": ["harness"],
        "taxonomy": {"severity": "high", "defect_class": "security",
                     "determinism": "deterministic", "fences": ["none"]},
        "outcome": outcome,
        "duplicate_target": None,
        "evidence_status": evidence,
    }


def inventory(items, raw=None, capture="complete"):
    return {"schema_version": "finding-candidate-inventory.v1", "capture_status": capture,
            "detector_completed": True if capture == "complete" else (False if capture == "partial" else None),
            "observed_at": OBSERVED_AT, "raw_candidates": len(items) if raw is None else raw,
            "candidates": items}


class ProducerTests(unittest.TestCase):
    def run_builder(self, data, config=CONFIG, issue_id="AIO-1099"):
        directory = tempfile.TemporaryDirectory()
        root = Path(directory.name)
        source = root / "inventory.json"
        generation = root / "generation"
        output = generation / "finding-observations.v1.jsonl"
        summary = generation / "finding-observations.v1.summary.json"
        source.write_text(json.dumps(data, separators=(",", ":")))
        args = SimpleNamespace(inventory=str(source), config=str(config), schema=str(SCHEMA),
                               program_id="AIO-1099", issue_id=issue_id,
                               harness_run_id="test-run", attempt=1)
        try:
            records = PRODUCER.build(args)
            PRODUCER.write_artifacts(generation, records)
            result = SimpleNamespace(returncode=0, stderr="")
        except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError) as error:
            result = SimpleNamespace(returncode=1, stderr=str(error))
        if result.returncode == 0 and validate is not None:
            validate(read_jsonl(output), json.loads(Path(config).read_text()))
        return directory, result, output, summary

    def test_verified_lifecycle_and_raw_reconciliation(self):
        directory, result, output, summary = self.run_builder(inventory([candidate()]))
        with directory:
            self.assertEqual(result.returncode, 0, result.stderr)
            records = [json.loads(line) for line in output.read_text().splitlines()]
            self.assertEqual([record.get("state") for record in records[:-1]], ["discovered", "verified"])
            self.assertEqual(records[-1]["counts"], {"raw_candidates": 1, "emitted_candidates": 1,
                                                     "terminal_stage": 1, "incomplete": 0, "malformed": 0})
            self.assertEqual(json.loads(summary.read_text())["event_id"], records[-1]["event_id"])
            self.assertEqual(oct(output.stat().st_mode & 0o777), "0o600")

    def test_malformed_is_counted_without_entering_digest_input(self):
        malformed = {"source_record_key": KEY}
        directory, result, output, _summary = self.run_builder(inventory([candidate(), malformed], raw=2))
        with directory:
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads(output.read_text().splitlines()[-1])
            self.assertEqual(summary["counts"], {"raw_candidates": 2, "emitted_candidates": 1,
                                                 "terminal_stage": 1, "incomplete": 1, "malformed": 1})
            self.assertEqual(summary["emission_gap_reason"], "malformed")
            self.assertNotIn("source_record_key", output.read_text().splitlines()[-1])

    def test_raw_count_cannot_claim_unenumerated_malformed_entries(self):
        directory, result, output, summary = self.run_builder(inventory([candidate()], raw=5))
        with directory:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid raw candidate count", result.stderr)
            self.assertFalse(output.exists())
            self.assertFalse(summary.exists())

    def test_input_order_and_rebuild_are_byte_stable(self):
        second = candidate({"kind": "position", "value": 9}, "incomplete", "incomplete")
        first = inventory([candidate(), second])
        d1, r1, o1, _ = self.run_builder(first)
        d2, r2, o2, _ = self.run_builder(inventory(list(reversed(first["candidates"]))))
        with d1, d2:
            self.assertEqual((r1.returncode, r2.returncode), (0, 0), r1.stderr + r2.stderr)
            self.assertEqual(o1.read_bytes(), o2.read_bytes())

    def test_unknown_is_not_a_clean_zero(self):
        data = inventory([], capture="unknown")
        data["raw_candidates"] = None
        directory, result, output, _ = self.run_builder(data)
        with directory:
            self.assertEqual(result.returncode, 0, result.stderr)
            summary = json.loads(output.read_text())
            self.assertEqual(summary["capture_status"], "unknown")
            self.assertTrue(all(value is None for value in summary["counts"].values()))

    def test_duplicate_resolution_and_incomplete_outcome(self):
        target_key = {"kind": "position", "value": 1}
        duplicate = candidate({"kind": "position", "value": 2}, "duplicate", "complete")
        duplicate["duplicate_target"] = target_key
        directory, result, output, _ = self.run_builder(inventory([candidate(target_key), duplicate]))
        with directory:
            self.assertEqual(result.returncode, 0, result.stderr)
            records = [json.loads(line) for line in output.read_text().splitlines()]
            duplicate_event = next(record for record in records if record.get("state") == "duplicate")
            self.assertNotEqual(duplicate_event["candidate_id"], duplicate_event["duplicate_target"])

    def test_raw_five_emits_five_with_all_discovery_outcomes(self):
        first_key = {"kind": "position", "value": 0}
        items = [candidate(first_key)]
        duplicate = candidate({"kind": "position", "value": 1}, "duplicate", "complete")
        duplicate["duplicate_target"] = first_key
        items.extend([
            duplicate,
            candidate({"kind": "position", "value": 2}, "rejected", "complete"),
            candidate({"kind": "position", "value": 3}),
            candidate({"kind": "position", "value": 4}, "incomplete", "incomplete"),
        ])
        directory, result, output, _ = self.run_builder(inventory(items, raw=5))
        with directory:
            self.assertEqual(result.returncode, 0, result.stderr)
            records = [json.loads(line) for line in output.read_text().splitlines()]
            latest = [record for record in records if record.get("sequence") == 1]
            self.assertCountEqual([record["state"] for record in latest],
                                  ["verified", "duplicate", "rejected", "verified", "incomplete"])
            self.assertEqual(records[-1]["counts"], {"raw_candidates": 5, "emitted_candidates": 5,
                                                     "terminal_stage": 4, "incomplete": 1, "malformed": 0})

    def test_privacy_and_registry_fail_closed_without_artifact(self):
        unsafe = candidate()
        unsafe["path"] = "private/source.py"
        directory, result, output, summary = self.run_builder(inventory([unsafe]))
        with directory:
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            self.assertFalse(summary.exists())
        with tempfile.TemporaryDirectory() as root:
            config = Path(root) / "config.json"
            altered = json.loads(CONFIG.read_text())
            altered["codebases"] = ["invalid/path"]
            config.write_text(json.dumps(altered))
            directory, result, output, _ = self.run_builder(inventory([candidate()]), config)
            with directory:
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(output.exists())

    def test_invalid_outcome_value_is_malformed_not_leaked(self):
        item = candidate()
        item["outcome"] = "bogus"
        directory, result, output, _ = self.run_builder(inventory([item]))
        with directory:
            self.assertEqual(result.returncode, 0, result.stderr)
            text = output.read_text()
            self.assertNotIn("bogus", text)
            self.assertEqual(json.loads(text)["counts"]["malformed"], 1)

    def test_unsafe_value_is_rejected_not_hashed(self):
        item = candidate()
        item["outcome"] = "https://example.invalid/private"
        directory, result, output, _ = self.run_builder(inventory([item]))
        with directory:
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())

    def test_issue_number_above_schema_bound_is_rejected(self):
        directory, result, output, summary = self.run_builder(
            inventory([candidate()]), issue_id="AIO-2147483648")
        with directory:
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("issue number exceeds contract bound", result.stderr)
            self.assertFalse(output.exists())
            self.assertFalse(summary.exists())

    def test_injected_publication_rename_failure_exposes_no_generation(self):
        directory, result, source, _ = self.run_builder(inventory([candidate()]))
        with directory, tempfile.TemporaryDirectory() as destination:
            self.assertEqual(result.returncode, 0, result.stderr)
            records = [json.loads(line) for line in source.read_text().splitlines()]
            generation = Path(destination) / "published-generation"
            with mock.patch.object(PRODUCER.os, "replace", side_effect=OSError("injected commit failure")):
                with self.assertRaises(OSError):
                    PRODUCER.write_artifacts(generation, records)
            self.assertFalse(generation.exists())
            self.assertEqual(list(Path(destination).iterdir()), [])


if __name__ == "__main__":
    unittest.main()
