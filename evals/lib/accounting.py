#!/usr/bin/env python3
"""Strict, zero-dependency accounting helpers for observations.v1."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any


COST_PROVENANCES = {
    "runtime_reported", "pricing_estimate", "allocated_subscription", "unknown",
}
TOKEN_KEYS = ("total_tokens", "input_tokens", "cached_input_tokens", "output_tokens", "reasoning_output_tokens")
PRICING_KEYS = ("catalog_version", "model", "service_tier", "currency", "timestamp", "formula")
ALLOCATION_KEYS = ("allocation_id", "allocation_basis", "attributable_to")
IDENTITY_KEYS = ("program_id", "issue_id", "phase", "attempt_id", "run_id")


def number(value: Any) -> int | float | None:
    return value if isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0 else None


def text(value: Any) -> str | None:
    return value if isinstance(value, str) and value else None


def complete(mapping: Any, keys: tuple[str, ...]) -> dict[str, str] | None:
    if not isinstance(mapping, dict):
        return None
    result = {key: text(mapping.get(key)) for key in keys}
    return result if all(result.values()) else None


def normalize_usage(usage: Any) -> dict[str, Any]:
    """Normalize usage without inferring missing totals or billing semantics."""
    raw = usage if isinstance(usage, dict) else {}
    input_tokens = number(raw.get("input_tokens"))
    cached_input_tokens = number(raw.get("cached_input_tokens"))
    if cached_input_tokens is None:
        cached_input_tokens = number(raw.get("cache_read_input_tokens"))
    output_tokens = number(raw.get("output_tokens"))
    reasoning_output_tokens = number(raw.get("reasoning_output_tokens"))
    total_tokens = number(raw.get("total_tokens"))
    if total_tokens is None:
        total_tokens = number(raw.get("tokens"))
    if total_tokens is None and input_tokens is not None and output_tokens is not None:
        total_tokens = input_tokens + output_tokens
    token_state = "reported" if any(value is not None for value in (
        total_tokens, input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens,
    )) else "unknown"

    legacy_cost = number(raw.get("cost_usd"))
    amount = number(raw.get("cost_amount"))
    if amount is None:
        amount = legacy_cost
    currency = text(raw.get("cost_currency"))
    if currency is None and legacy_cost is not None:
        currency = "USD"
    requested = raw.get("cost_provenance", raw.get("cost_state", "unknown"))
    provenance = requested if requested in COST_PROVENANCES else "unknown"
    pricing = complete(raw.get("pricing"), PRICING_KEYS)
    allocation = complete(raw.get("allocation"), ALLOCATION_KEYS)
    valid_cost = amount is not None and currency is not None
    if provenance == "pricing_estimate":
        valid_cost = valid_cost and pricing is not None and pricing["currency"] == currency
    elif provenance == "allocated_subscription":
        valid_cost = valid_cost and allocation is not None
    elif provenance == "runtime_reported":
        valid_cost = valid_cost
    else:
        valid_cost = False
    state = provenance if valid_cost else "unknown"
    unclassified = None
    if amount is not None and state == "unknown":
        unclassified = {"amount": amount, "currency": currency or "unknown"}
    return {
        "tokens": total_tokens,
        "total_tokens": total_tokens,
        "input_tokens": input_tokens,
        "cached_input_tokens": cached_input_tokens,
        "cache_read_input_tokens": cached_input_tokens,
        "output_tokens": output_tokens,
        "reasoning_output_tokens": reasoning_output_tokens,
        "token_state": token_state,
        "cost_usd": amount if state != "unknown" and currency == "USD" else None,
        "cost_amount": amount if state != "unknown" else None,
        "cost_currency": currency if state != "unknown" else None,
        "cost_state": state,
        "cost_provenance": state,
        "pricing": pricing if state == "pricing_estimate" else None,
        "allocation": allocation if state == "allocated_subscription" else None,
        "unclassified_runtime_cost": unclassified,
    }


def attempt_from_driver(driver: dict[str, Any], identity: dict[str, Any]) -> dict[str, Any]:
    """Create a backward-compatible, stable attempt record from one driver record."""
    run_id = text(identity.get("run_id")) or "unknown"
    attempt_id = text(identity.get("attempt_id")) or run_id
    return {
        "program_id": text(identity.get("program_id")) or "unknown",
        "issue_id": text(identity.get("issue_id")) or "unknown",
        "phase": text(identity.get("phase")) or "unknown",
        "attempt_id": attempt_id,
        "run_id": run_id,
        "role": text(identity.get("role")) or "unknown",
        "runtime": text(driver.get("runtime")) or "unknown",
        "model": text(driver.get("model")) or "unknown",
        "outcome_verified": identity.get("outcome_verified") is True,
        "usage": normalize_usage(driver.get("usage")),
    }


def attempt_identity(attempt: dict[str, Any]) -> tuple[str, ...]:
    return tuple(text(attempt.get(key)) or "unknown" for key in IDENTITY_KEYS)


def canonical_attempt(attempt: dict[str, Any]) -> str:
    return json.dumps(attempt, sort_keys=True, separators=(",", ":"))


def aggregate_attempts(records: list[dict[str, Any]]) -> dict[str, Any]:
    """Aggregate distinct attempts, rejecting ambiguous identity collisions."""
    unique: dict[tuple[str, ...], dict[str, Any]] = {}
    deduplicated_replays = 0
    for raw in records:
        attempt = dict(raw)
        attempt["usage"] = normalize_usage(raw.get("usage"))
        key = attempt_identity(attempt)
        previous = unique.get(key)
        if previous is None:
            unique[key] = attempt
        elif canonical_attempt(previous) == canonical_attempt(attempt):
            deduplicated_replays += 1
        else:
            raise ValueError("conflicting duplicate identity: " + "/".join(key))

    attempts = [unique[key] for key in sorted(unique)]
    dimensions: dict[str, Any] = {}
    for key in TOKEN_KEYS:
        values = [attempt["usage"][key] for attempt in attempts]
        known = [value for value in values if value is not None]
        unknown = len(values) - len(known)
        dimensions[key] = sum(known) if unknown == 0 else None
        dimensions["known_" + key] = sum(known) if known else None
        dimensions[key + "_unknown_attempts"] = unknown
    dimensions["unknown_attempts"] = dimensions["total_tokens_unknown_attempts"]
    costs: dict[str, Any] = {
        "runtime_reported": {}, "pricing_estimate": {}, "allocated_subscription": {},
        "unclassified_runtime": {}, "unknown_attempts": 0,
    }
    for attempt in attempts:
        usage = attempt["usage"]
        state = usage["cost_state"]
        if state == "unknown":
            costs["unknown_attempts"] += 1
            unclassified = usage["unclassified_runtime_cost"]
            if unclassified:
                currency = unclassified["currency"]
                costs["unclassified_runtime"][currency] = costs["unclassified_runtime"].get(currency, 0) + unclassified["amount"]
            continue
        currency = usage["cost_currency"]
        bucket = costs[state]
        bucket[currency] = bucket.get(currency, 0) + usage["cost_amount"]
    return {
        "attempt_count": len(attempts),
        "deduplicated_replays": deduplicated_replays,
        "outcome_count": sum(attempt.get("outcome_verified") is True for attempt in attempts),
        "attempts": attempts,
        "tokens": dimensions,
        "costs": costs,
    }


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser(description="aggregate observations.v1 accounting")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()
    attempts: list[dict[str, Any]] = []
    try:
        for path in args.runs:
            run = json.loads(path.read_text())
            if not isinstance(run, dict):
                raise ValueError("run record is not an object: " + path.name)
            attempts.append(attempt_from_driver(run, run))
        args.output.write_text(json.dumps(aggregate_attempts(attempts), separators=(",", ":")) + "\n")
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print("accounting: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
