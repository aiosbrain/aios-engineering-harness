#!/usr/bin/env python3
"""Strict, zero-dependency accounting helpers for observations.v1."""

from __future__ import annotations

import json
import math
import re
import sys
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


COST_PROVENANCES = {"runtime_reported", "pricing_estimate", "allocated_subscription", "unknown"}
TOKEN_KEYS = ("total_tokens", "input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens")
IDENTITY_KEYS = ("program_id", "issue_id", "phase", "attempt_id", "invocation_id", "run_id")
LOGICAL_ATTEMPT_KEYS = ("program_id", "issue_id", "phase", "attempt_id")
SHA_RE = re.compile(r"^[0-9a-f]{40,64}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_JSON_SAFE_INTEGER = 9_007_199_254_740_991


def text(value: Any) -> str | None:
    return value if isinstance(value, str) and value.strip() else None


def token(value: Any) -> int | None:
    return value if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= MAX_JSON_SAFE_INTEGER else None


def decimal(value: Any) -> Decimal | None:
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        return None
    if isinstance(value, float) and not math.isfinite(value):
        return None
    try:
        parsed = Decimal(str(value))
    except (InvalidOperation, ValueError):
        return None
    return parsed if parsed.is_finite() and parsed >= 0 else None


def amount_value(value: Any) -> int | float | None:
    parsed = decimal(value)
    if parsed is None:
        return None
    return int(parsed) if parsed == parsed.to_integral_value() else float(parsed)


def runtime_cost(value: Any) -> Decimal | None:
    """Accept only finite, nonnegative JSON-safe runtime cost magnitudes."""
    parsed = decimal(value)
    return parsed if parsed is not None and parsed <= MAX_JSON_SAFE_INTEGER else None


def currency(value: Any) -> str | None:
    candidate = text(value)
    return candidate if candidate and re.fullmatch(r"[A-Z]{3}", candidate) else None


def iso_timestamp(value: Any) -> str | None:
    candidate = text(value)
    if not candidate:
        return None
    try:
        parsed = datetime.fromisoformat(candidate.replace("Z", "+00:00"))
    except ValueError:
        return None
    return candidate if parsed.tzinfo is not None else None


def token_dimensions(raw: dict[str, Any]) -> dict[str, int | None]:
    cached = raw.get("cached_input_tokens")
    if cached is None:
        cached = raw.get("cache_read_input_tokens")
    return {
        "total_tokens": token(raw.get("total_tokens", raw.get("tokens"))),
        "input_tokens": token(raw.get("input_tokens")),
        "cached_input_tokens": token(cached),
        "output_tokens": token(raw.get("output_tokens")),
        "reasoning_output_tokens": token(raw.get("reasoning_output_tokens")),
    }


def token_state(dimensions: dict[str, int | None]) -> str:
    present = sum(value is not None for value in dimensions.values())
    return "unknown" if present == 0 else ("complete" if present == len(TOKEN_KEYS) else "partial")


def pricing_provenance(raw: Any, amount: Decimal | None, cost_currency: str | None) -> dict[str, Any] | None:
    if not isinstance(raw, dict) or amount is None or cost_currency is None:
        return None
    required = ("catalog_version", "model", "service_tier")
    if any(text(raw.get(key)) is None for key in required):
        return None
    pricing_currency = currency(raw.get("currency"))
    timestamp = iso_timestamp(raw.get("timestamp"))
    if pricing_currency != cost_currency or timestamp is None or raw.get("formula_method") != "token_rate_v1":
        return None
    inputs = raw.get("inputs")
    if not isinstance(inputs, dict):
        return None
    counts = inputs.get("token_counts")
    rates = inputs.get("rates_per_token")
    if not isinstance(counts, dict) or not isinstance(rates, dict):
        return None
    normalized_counts = {key: token(counts.get(key)) for key in TOKEN_KEYS}
    normalized_rates = {key: decimal(rates.get(key)) for key in TOKEN_KEYS}
    if any(value is None for value in normalized_counts.values()) or any(value is None for value in normalized_rates.values()):
        return None
    # Total, cached input, and reasoning output overlap their parent dimensions. The
    # method prices only disjoint portions, so telemetry is never double-counted.
    if normalized_rates["total_tokens"] != 0 or normalized_counts["cached_input_tokens"] > normalized_counts["input_tokens"] or \
            normalized_counts["reasoning_output_tokens"] > normalized_counts["output_tokens"]:
        return None
    calculated = (
        Decimal(normalized_counts["input_tokens"] - normalized_counts["cached_input_tokens"]) * normalized_rates["input_tokens"] +
        Decimal(normalized_counts["cached_input_tokens"]) * normalized_rates["cached_input_tokens"] +
        Decimal(normalized_counts["output_tokens"] - normalized_counts["reasoning_output_tokens"]) * normalized_rates["output_tokens"] +
        Decimal(normalized_counts["reasoning_output_tokens"]) * normalized_rates["reasoning_output_tokens"]
    )
    if calculated != amount:
        return None
    return {
        "catalog_version": raw["catalog_version"], "model": raw["model"], "service_tier": raw["service_tier"],
        "currency": pricing_currency, "timestamp": timestamp, "formula_method": "token_rate_v1",
        "inputs": {"token_counts": normalized_counts,
                   "rates_per_token": {key: amount_value(value) for key, value in normalized_rates.items()}},
    }


def allocation_provenance(raw: Any, amount: Decimal | None, cost_currency: str | None) -> dict[str, Any] | None:
    if not isinstance(raw, dict) or amount is None or cost_currency is None:
        return None
    required = ("allocation_id", "allocation_basis", "attributable_to", "rule_version")
    if any(text(raw.get(key)) is None for key in required) or raw.get("method") != "proportional_allocation_v1":
        return None
    timestamp = iso_timestamp(raw.get("timestamp"))
    inputs = raw.get("inputs")
    if timestamp is None or not isinstance(inputs, dict):
        return None
    subscription_amount = decimal(inputs.get("subscription_amount"))
    numerator = decimal(inputs.get("numerator"))
    denominator = decimal(inputs.get("denominator"))
    if subscription_amount is None or numerator is None or denominator is None or denominator == 0:
        return None
    if subscription_amount * numerator / denominator != amount:
        return None
    return {
        "allocation_id": raw["allocation_id"], "allocation_basis": raw["allocation_basis"],
        "attributable_to": raw["attributable_to"], "rule_version": raw["rule_version"],
        "timestamp": timestamp, "method": "proportional_allocation_v1",
        "inputs": {"subscription_amount": amount_value(subscription_amount), "numerator": amount_value(numerator),
                   "denominator": amount_value(denominator)},
    }


def runtime_provenance(raw: Any) -> dict[str, str] | None:
    if not isinstance(raw, dict):
        return None
    source_field = text(raw.get("source_field"))
    semantics = text(raw.get("semantics"))
    if not source_field or semantics != "runtime_reported_not_billed_or_actual":
        return None
    return {"source_field": source_field, "semantics": semantics}


def normalize_usage(usage: Any) -> dict[str, Any]:
    """Normalize usage without deriving absent totals or billing semantics."""
    raw = usage if isinstance(usage, dict) else {}
    dimensions = token_dimensions(raw)
    state = token_state(dimensions)
    raw_amount = raw.get("cost_amount", raw.get("cost_usd"))
    parsed_amount = runtime_cost(raw_amount)
    legacy_cost = raw.get("cost_usd")
    cost_currency = currency(raw.get("cost_currency"))
    if cost_currency is None and parsed_amount is not None and legacy_cost is not None:
        cost_currency = "USD"
    requested = raw.get("cost_provenance", raw.get("cost_state", "unknown"))
    provenance = requested if requested in COST_PROVENANCES else "unknown"
    pricing = pricing_provenance(raw.get("pricing"), parsed_amount, cost_currency) if provenance == "pricing_estimate" else None
    allocation = allocation_provenance(raw.get("allocation"), parsed_amount, cost_currency) if provenance == "allocated_subscription" else None
    runtime = runtime_provenance(raw.get("runtime_cost")) if provenance == "runtime_reported" else None
    valid = (provenance == "pricing_estimate" and pricing is not None) or \
        (provenance == "allocated_subscription" and allocation is not None) or \
        (provenance == "runtime_reported" and runtime is not None and parsed_amount is not None and cost_currency is not None)
    cost_state = provenance if valid else "unknown"
    unclassified = None
    if parsed_amount is not None and cost_state == "unknown":
        unclassified = {"amount": amount_value(parsed_amount), "currency": cost_currency or "unknown"}
    return {
        "tokens": dimensions["total_tokens"], **dimensions,
        "cache_read_input_tokens": dimensions["cached_input_tokens"],
        "token_state": state,
        "usage_state": "reported" if state != "unknown" or parsed_amount is not None else "unknown",
        "cost_usd": amount_value(parsed_amount) if cost_state != "unknown" and cost_currency == "USD" else None,
        "cost_amount": amount_value(parsed_amount) if cost_state != "unknown" else None,
        "cost_currency": cost_currency if cost_state != "unknown" else None,
        "cost_state": cost_state, "cost_provenance": cost_state,
        "pricing": pricing if cost_state == "pricing_estimate" else None,
        "allocation": allocation if cost_state == "allocated_subscription" else None,
        "runtime_cost": runtime if cost_state == "runtime_reported" else None,
        "unclassified_runtime_cost": unclassified,
    }


def sha(value: Any) -> str | None:
    candidate = text(value)
    return candidate if candidate and SHA_RE.fullmatch(candidate) else None


def normalize_evidence(value: Any) -> list[dict[str, str]] | None:
    if not isinstance(value, list) or not value:
        return None
    evidence: list[dict[str, str]] = []
    for item in value:
        if not isinstance(item, dict):
            return None
        basename = text(item.get("basename"))
        digest = text(item.get("sha256"))
        if not basename or not digest or not SHA256_RE.fullmatch(digest) or "/" in basename or "\\" in basename:
            return None
        evidence.append({"basename": basename, "sha256": digest})
    return sorted(evidence, key=lambda item: (item["basename"], item["sha256"]))


def encoded_identity(values: tuple[str, ...]) -> str:
    """Produce a compact, reversible identity without delimiter collisions."""
    return json.dumps(list(values), separators=(",", ":"), ensure_ascii=True)


def normalize_verified_outcome(attempt: dict[str, Any]) -> dict[str, Any] | None:
    raw = attempt.get("verified_outcome")
    if not isinstance(raw, dict):
        return None
    outcome_id = text(raw.get("outcome_id"))
    verification_id = text(raw.get("verification_id"))
    reviewed_sha = sha(raw.get("reviewed_sha"))
    evidence = normalize_evidence(raw.get("evidence"))
    role = text(raw.get("verifier_role"))
    subject_attempt_id = text(raw.get("subject_attempt_id"))
    if not outcome_id or not verification_id or not subject_attempt_id or role not in {"reviewer", "verifier"} or raw.get("terminal_status") != "pass" or raw.get("decision") != "READY":
        return None
    if attempt.get("role") != role or verification_id != attempt.get("attempt_id"):
        return None
    if attempt.get("status") != "pass" or attempt.get("exit_status") != 0 or attempt.get("observation_verdict") != "pass":
        return None
    sources = normalize_evidence(attempt.get("source_artifacts"))
    required = {"driver.json", "observations.v1.summary.json", "final.md"}
    if reviewed_sha is None or reviewed_sha != sha(attempt.get("current_sha")) or evidence is None or sources is None:
        return None
    if len(evidence) != len(required) or {item["basename"] for item in evidence} != required:
        return None
    source_by_name = {item["basename"]: item["sha256"] for item in sources}
    if any(source_by_name.get(item["basename"]) != item["sha256"] for item in evidence):
        return None
    canonical_id = encoded_identity((text(attempt.get("program_id")) or "unknown", text(attempt.get("issue_id")) or "unknown", reviewed_sha))
    return {"outcome_id": canonical_id, "display_outcome_id": outcome_id, "verification_id": verification_id,
            "verifier_role": role, "subject_attempt_id": subject_attempt_id, "terminal_status": "pass",
            "reviewed_sha": reviewed_sha, "decision": "READY", "evidence": evidence,
            "verifier_identity": attempt_identity(attempt)}


def attempt_from_driver(driver: dict[str, Any], identity: dict[str, Any]) -> dict[str, Any]:
    """Create a stable attempt record from one run record while retaining legacy fields."""
    run_id = text(identity.get("run_id")) or "unknown"
    return {
        "invocation_id": text(identity.get("invocation_id")) or "legacy",
        "program_id": text(identity.get("program_id")) or "unknown", "issue_id": text(identity.get("issue_id")) or "unknown",
        "phase": text(identity.get("phase")) or "unknown", "attempt_id": text(identity.get("attempt_id")) or run_id,
        "run_id": run_id, "role": text(identity.get("role")) or "unknown",
        "runtime": text(driver.get("runtime")) or "unknown", "model": text(driver.get("model")) or "unknown",
        "status": text(identity.get("status")) or "unknown", "exit_status": identity.get("exit_status"),
        "current_sha": text(identity.get("current_sha")) or "unknown", "reviewed_sha": text(identity.get("reviewed_sha")) or "unknown",
        "observation_verdict": text(identity.get("observation_verdict")) or "unknown",
        "usage": normalize_usage(driver.get("usage")), "verified_outcome": identity.get("verified_outcome"),
        "source_artifacts": identity.get("source_artifacts"),
    }


def attempt_identity(attempt: dict[str, Any]) -> tuple[str, ...]:
    return tuple(text(attempt.get(key)) or "unknown" for key in IDENTITY_KEYS)


def logical_attempt_identity(attempt: dict[str, Any]) -> tuple[str, ...]:
    return tuple(text(attempt.get(key)) or "unknown" for key in LOGICAL_ATTEMPT_KEYS)


def canonical_attempt(attempt: dict[str, Any]) -> str:
    return json.dumps(attempt, sort_keys=True, separators=(",", ":"), allow_nan=False)


def summarize(attempts: list[dict[str, Any]]) -> dict[str, Any]:
    dimensions: dict[str, Any] = {}
    for key in TOKEN_KEYS:
        values = [attempt["usage"][key] for attempt in attempts]
        known = [value for value in values if value is not None]
        unknown = len(values) - len(known)
        dimensions[key] = sum(known) if unknown == 0 else None
        dimensions["known_" + key] = sum(known) if known else None
        dimensions[key + "_unknown_attempts"] = unknown
    dimensions["unknown_attempts"] = dimensions["total_tokens_unknown_attempts"]
    costs: dict[str, Any] = {"runtime_reported": {}, "pricing_estimate": {}, "allocated_subscription": {},
                             "unclassified_runtime": {}, "unknown_attempts": 0}
    statuses: dict[str, int] = {}
    for attempt in attempts:
        statuses[attempt["status"]] = statuses.get(attempt["status"], 0) + 1
        usage = attempt["usage"]
        if usage["cost_state"] == "unknown":
            costs["unknown_attempts"] += 1
            unclassified = usage["unclassified_runtime_cost"]
            if unclassified:
                current = Decimal(str(costs["unclassified_runtime"].get(unclassified["currency"], 0)))
                costs["unclassified_runtime"][unclassified["currency"]] = amount_value(current + Decimal(str(unclassified["amount"])))
            continue
        bucket = costs[usage["cost_state"]]
        current = Decimal(str(bucket.get(usage["cost_currency"], 0)))
        bucket[usage["cost_currency"]] = amount_value(current + Decimal(str(usage["cost_amount"])))
    return {"attempt_count": len(attempts), "by_status": statuses, "tokens": dimensions, "costs": costs}


def terminal_subject(attempt: dict[str, Any], verifier: dict[str, Any], subject_attempt_id: str, reviewed_sha: str) -> bool:
    return attempt.get("program_id") == verifier.get("program_id") and attempt.get("issue_id") == verifier.get("issue_id") and \
        attempt.get("attempt_id") == subject_attempt_id and attempt.get("role") in {"writer", "implementer"} and \
        attempt.get("status") == "pass" and attempt.get("exit_status") == 0 and attempt.get("observation_verdict") == "pass" and \
        sha(attempt.get("current_sha")) == reviewed_sha and attempt_identity(attempt) != attempt_identity(verifier)


def verified_outcomes(attempts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    outcomes: dict[str, dict[str, Any]] = {}
    for attempt in attempts:
        outcome = normalize_verified_outcome(attempt)
        if outcome is None:
            continue
        if not any(terminal_subject(subject, attempt, outcome["subject_attempt_id"], outcome["reviewed_sha"]) for subject in attempts):
            continue
        previous = outcomes.get(outcome["outcome_id"])
        # Verifier retries have fresh immutable evidence hashes. They represent one
        # outcome when their program/issue/SHA/subject decision agree; changing any
        # of those canonical facts fails closed.
        ignored = {"verification_id", "verifier_identity", "display_outcome_id", "evidence"}
        comparable = {key: value for key, value in outcome.items() if key not in ignored}
        if previous is not None and {key: value for key, value in previous.items() if key not in ignored} != comparable:
            raise ValueError("conflicting verified outcome: " + outcome["outcome_id"])
        outcomes.setdefault(outcome["outcome_id"], outcome)
    return [outcomes[key] for key in sorted(outcomes)]


def aggregate_attempts(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Deduplicate attempts once, then group the same unique records into rollups."""
    unique: dict[tuple[str, ...], dict[str, Any]] = {}
    deduplicated_replays = 0
    for raw in records:
        attempt = attempt_from_driver(raw, raw)
        key = attempt_identity(attempt)
        previous = unique.get(key)
        if previous is None:
            unique[key] = attempt
        elif canonical_attempt(previous) == canonical_attempt(attempt):
            deduplicated_replays += 1
        else:
            raise ValueError("conflicting duplicate identity: " + encoded_identity(key))
    attempts = [unique[key] for key in sorted(unique)]
    outcomes = verified_outcomes(attempts)
    def with_outcomes(items: list[dict[str, Any]], scoped: list[dict[str, Any]]) -> dict[str, Any]:
        result = summarize(items)
        ids = sorted({outcome["outcome_id"] for outcome in scoped})
        result.update({"independently_verified_outcome_count": len(ids), "independently_verified_outcome_ids": ids,
                       "outcome_count": len(ids)})
        return result

    overall = with_outcomes(attempts, outcomes)
    by_attempt: dict[str, dict[str, Any]] = {}
    for key in sorted({logical_attempt_identity(attempt) for attempt in attempts}):
        group = [attempt for attempt in attempts if logical_attempt_identity(attempt) == key]
        scoped = [outcome for outcome in outcomes if logical_attempt_identity(next(attempt for attempt in attempts if attempt_identity(attempt) == outcome["verifier_identity"])) == key]
        by_attempt[encoded_identity(key)] = with_outcomes(group, scoped)
    rollups: dict[str, Any] = {"by_attempt": by_attempt, "by_phase": {}, "by_issue": {}, "by_program": {},
                               "overall_unique_attempts": overall}
    for level in ("phase", "issue_id", "program_id"):
        groups: dict[str, list[dict[str, Any]]] = {}
        for attempt in attempts:
            groups.setdefault(attempt[level], []).append(attempt)
        target = {"phase": "by_phase", "issue_id": "by_issue", "program_id": "by_program"}[level]
        rollups[target] = {key: with_outcomes(groups[key], [outcome for outcome in outcomes if next(attempt for attempt in attempts if attempt_identity(attempt) == outcome["verifier_identity"])[level] == key]) for key in sorted(groups)}
    return {**overall, "deduplicated_replays": deduplicated_replays,
            "verified_outcomes": outcomes, "attempts": attempts, "rollups": rollups}


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="aggregate observations.v1 accounting")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        records = []
        for path in args.runs:
            run = json.loads(path.read_text())
            if not isinstance(run, dict):
                raise ValueError("run record is not an object: " + path.name)
            records.append(run)
        args.output.write_text(json.dumps(aggregate_attempts(records), separators=(",", ":"), allow_nan=False) + "\n")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print("accounting: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
