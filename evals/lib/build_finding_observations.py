#!/usr/bin/env python3
"""Build the closed finding-observations v1 ledger from a sanitized inventory."""
import argparse
import hashlib
import json
import os
import re
import shutil
import stat
import tempfile
from datetime import datetime
from pathlib import Path

DOMAIN_CANDIDATE = "aios.finding.candidate.discovery.v1"
DOMAIN_EVENT = "aios.finding.event.v1"
DOMAIN_RUN = "aios.finding.producer.run.v1"
DOMAIN_ATTR = "aios.finding.attribution.v1"
SCHEMA_SHA256 = "a51f360769ab26440287891867447baf6e3df93073df6f0d7febc1f3c10322b2"
PRODUCER = "harness"
VERSION = "1.0.0"
MAX_INT = 2147483647
ENUMS = {
    "severity": {"critical", "high", "medium", "low", "unknown"},
    "defect_class": {"logic", "security", "gate-integrity", "test-integrity", "verifiability", "contract-drift", "docs", "perf", "unknown"},
    "determinism": {"deterministic", "flaky", "unverified", "unknown"},
    "fences": {"none", "migration", "credential", "schema", "public-api", "release", "unknown"},
    "outcome": {"verified", "duplicate", "rejected", "incomplete"},
    "evidence_status": {"complete", "incomplete", "unknown"},
}
CANDIDATE_KEYS = {"source_record_key", "codebases", "taxonomy", "outcome", "duplicate_target", "evidence_status"}
INVENTORY_KEYS = {"schema_version", "capture_status", "detector_completed", "observed_at", "raw_candidates", "candidates"}
SENSITIVE_KEYS = {"description", "url", "path", "excerpt", "patch", "prompt", "transcript", "credential", "contributor"}
SLUG = re.compile(r"[a-z][a-z0-9-]{0,47}\Z")
DIGEST = re.compile(r"[0-9a-f]{64}\Z")
TIMESTAMP = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\Z")
SAFE_SEED = re.compile(r"[A-Za-z0-9][A-Za-z0-9:._-]{0,127}\Z")


def require(condition, message):
    if not condition:
        raise ValueError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode()


def digest(domain, value):
    return hashlib.sha256(domain.encode("ascii") + b"\0" + canonical(value)).hexdigest()


def event_id(record):
    return digest(DOMAIN_EVENT, {key: value for key, value in record.items() if key != "event_id"})


def strict_load(path):
    def pairs(items):
        result = {}
        for key, value in items:
            require(key not in result, "duplicate JSON key")
            result[key] = value
        return result

    def reject_number(_value):
        raise ValueError("non-integer JSON numeric token")

    raw = Path(path).read_bytes()
    require(not raw.startswith(b"\xef\xbb\xbf"), "BOM is forbidden")
    return json.loads(raw.decode("utf-8"), object_pairs_hook=pairs,
                      parse_float=reject_number, parse_constant=reject_number)


def check_privacy(value):
    if isinstance(value, dict):
        for key, item in value.items():
            require(key not in SENSITIVE_KEYS, "unsafe inventory field")
            check_privacy(item)
    elif isinstance(value, list):
        for item in value:
            check_privacy(item)
    elif isinstance(value, str):
        require(not any(character.isspace() for character in value) and
                "/" not in value and "\\" not in value and "@" not in value and "://" not in value,
                "unsafe inventory string")


def validate_registry(config, schema_path):
    require(isinstance(config, dict) and set(config) == {"schema_sha256", "producers", "codebases", "linear_teams"}, "invalid trusted registry")
    require(config["schema_sha256"] == SCHEMA_SHA256, "untrusted schema pin")
    actual = hashlib.sha256(Path(schema_path).read_bytes()).hexdigest()
    require(actual == SCHEMA_SHA256, "schema hash mismatch")
    producers = config["producers"]
    require(isinstance(producers, dict) and PRODUCER in producers, "producer is not registered")
    require(isinstance(producers[PRODUCER], list) and VERSION in producers[PRODUCER], "producer version is not registered")
    require(all(isinstance(name, str) and SLUG.fullmatch(name) and isinstance(versions, list) and
                versions == sorted(set(versions)) and versions and
                all(isinstance(version, str) and re.fullmatch(r"[0-9]{1,4}\.[0-9]{1,4}\.[0-9]{1,4}", version) for version in versions)
                for name, versions in producers.items()), "invalid producer registry entry")
    codebases = config["codebases"]
    require(isinstance(codebases, list) and codebases == sorted(set(codebases)) and all(SLUG.fullmatch(x) for x in codebases), "invalid codebase registry")
    teams = config["linear_teams"]
    require(isinstance(teams, list) and teams == sorted(set(teams)) and all(re.fullmatch(r"[A-Z][A-Z0-9]{1,9}", x) for x in teams), "invalid Linear team registry")


def validate_timestamp(value):
    require(isinstance(value, str) and TIMESTAMP.fullmatch(value), "invalid observation timestamp")
    datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")


def valid_key(value):
    if not isinstance(value, dict) or set(value) != {"kind", "value"}:
        return False
    if value["kind"] == "position":
        return type(value["value"]) is int and 0 <= value["value"] <= MAX_INT
    return value["kind"] == "structural_sha256" and isinstance(value["value"], str) and bool(DIGEST.fullmatch(value["value"]))


def sanitize_candidate(candidate, config):
    if not isinstance(candidate, dict) or set(candidate) != CANDIDATE_KEYS:
        return None
    key = candidate["source_record_key"]
    codebases = candidate["codebases"]
    taxonomy = candidate["taxonomy"]
    outcome = candidate["outcome"]
    evidence = candidate["evidence_status"]
    duplicate = candidate["duplicate_target"]
    if not valid_key(key) or not isinstance(codebases, list) or not codebases:
        return None
    require(codebases == sorted(set(codebases)) and set(codebases) <= set(config["codebases"]), "untrusted or noncanonical codebase")
    if not isinstance(taxonomy, dict) or set(taxonomy) != {"severity", "defect_class", "determinism", "fences"}:
        return None
    fences = taxonomy["fences"]
    if any(taxonomy.get(field) not in ENUMS[field] for field in ("severity", "defect_class", "determinism")) or not isinstance(fences, list) or not fences:
        return None
    require(fences == sorted(set(fences)) and set(fences) <= ENUMS["fences"], "invalid or noncanonical fences")
    require(not ({"none", "unknown"} & set(fences)) or len(fences) == 1, "exclusive fence mixed")
    if outcome not in ENUMS["outcome"] or evidence not in ENUMS["evidence_status"]:
        return None
    require((outcome == "incomplete") == (evidence != "complete"), "outcome/evidence mismatch")
    require((outcome == "duplicate") == (duplicate is not None), "duplicate target mismatch")
    if duplicate is not None:
        require(valid_key(duplicate), "invalid duplicate target")
    return {key_: candidate[key_] for key_ in sorted(CANDIDATE_KEYS)}


def attribution(args, config):
    require(SAFE_SEED.fullmatch(args.program_id) and SAFE_SEED.fullmatch(args.harness_run_id),
            "unsafe attribution seed")
    issue = None
    match = re.fullmatch(r"([A-Z][A-Z0-9]{1,9})-([1-9][0-9]*)", args.issue_id)
    if match:
        require(match.group(1) in config["linear_teams"], "untrusted attribution team")
        issue_number = int(match.group(2))
        require(issue_number <= MAX_INT, "issue number exceeds contract bound")
        issue = {"type": "linear", "team": match.group(1), "number": issue_number}
    return {
        "program_id": hashlib.sha256(("program\0" + args.program_id).encode()).hexdigest(),
        "run_id": hashlib.sha256(("harness-run\0" + args.harness_run_id).encode()).hexdigest(),
        "attempt": args.attempt,
        "issue": issue,
    }


def base_record(producer, attr, observed_at, evidence):
    return {"schema_version": "finding-observations.v1", "visibility_tier": "team",
            "event_id": "", "producer": producer, "observed_at": observed_at,
            "evidence_status": evidence, "attribution": attr}


def seal(record):
    record["event_id"] = event_id(record)
    return record


def candidate_event(base, candidate_id, identity, item, state, sequence, predecessor):
    record = dict(base)
    record.update({"record_type": "candidate", "candidate_id": candidate_id, "identity": identity,
                   "codebases": item["codebases"], "taxonomy": item["taxonomy"], "state": state,
                   "disposition": {"duplicate": "duplicate", "rejected": "rejected", "incomplete": "unknown"}.get(state, "open"),
                   "sequence": sequence, "predecessor_event_id": predecessor, "episode": 0,
                   "duplicate_target": None, "links": {"linear": None, "scanner": None, "pull_request": None, "merge": None, "resolution": None}})
    return seal(record)


def validate_output(records, config):
    require(records and records[-1]["record_type"] == "run_summary", "summary missing")
    ids, latest = set(), {}
    for record in records:
        require(record["event_id"] == event_id(record) and record["event_id"] not in ids, "invalid or repeated event")
        ids.add(record["event_id"])
        if record["record_type"] == "candidate":
            require(set(record["codebases"]) <= set(config["codebases"]), "unregistered output codebase")
            cid = record["candidate_id"]
            require(cid == digest(DOMAIN_CANDIDATE, record["identity"]), "invalid candidate identity")
            prior = latest.get(cid)
            require(record["sequence"] == (0 if prior is None else prior["sequence"] + 1), "lifecycle gap")
            require(record["predecessor_event_id"] == (None if prior is None else prior["event_id"]), "bad predecessor")
            latest[cid] = record
    summary = records[-1]
    counts = summary["counts"]
    if summary["capture_status"] == "unknown":
        require(all(value is None for value in counts.values()), "unknown capture has counts")
    else:
        terminal = sum(item["state"] in {"verified", "duplicate", "rejected"} for item in latest.values())
        require(counts["emitted_candidates"] == len(latest) and counts["terminal_stage"] == terminal, "summary reconciliation failed")
        require(counts["raw_candidates"] == terminal + counts["incomplete"], "raw reconciliation failed")
        require(counts["raw_candidates"] - counts["emitted_candidates"] == counts["malformed"], "malformed reconciliation failed")


def build(args):
    config = strict_load(args.config)
    validate_registry(config, args.schema)
    inventory = strict_load(args.inventory)
    check_privacy(inventory)
    require(isinstance(inventory, dict) and set(inventory) == INVENTORY_KEYS, "invalid inventory envelope")
    require(inventory["schema_version"] == "finding-candidate-inventory.v1", "unsupported inventory")
    capture = inventory["capture_status"]
    require(capture in {"complete", "partial", "unknown"}, "invalid capture status")
    validate_timestamp(inventory["observed_at"])
    raw = inventory["raw_candidates"]
    candidates = inventory["candidates"]
    require(isinstance(candidates, list), "candidate inventory must be an array")
    if capture == "unknown":
        require(inventory["detector_completed"] is None and raw is None and not candidates, "unknown capture claims a denominator")
    else:
        require(inventory["detector_completed"] is (capture == "complete"), "capture completion mismatch")
        require(type(raw) is int and 0 <= raw <= MAX_INT and raw >= len(candidates), "invalid raw candidate count")
        require(raw != 0 or capture == "complete", "partial capture cannot prove empty")
    sanitized = []
    for item in candidates:
        value = sanitize_candidate(item, config)
        if value is not None:
            sanitized.append(value)
    key_bytes = [canonical(item["source_record_key"]) for item in sanitized]
    require(len(key_bytes) == len(set(key_bytes)), "duplicate source record key")
    sanitized.sort(key=lambda item: canonical(item["source_record_key"]))
    projection = {"schema_version": inventory["schema_version"], "capture_status": capture,
                  "detector_completed": inventory["detector_completed"], "observed_at": inventory["observed_at"],
                  "raw_candidates": raw, "candidates": sanitized,
                  "malformed_candidates": None if raw is None else raw - len(sanitized)}
    source_hash = hashlib.sha256(canonical(projection)).hexdigest()
    attr = attribution(args, config)
    run_id = digest(DOMAIN_RUN, {"inventory": projection, "attribution": attr})
    producer = {"name": PRODUCER, "version": VERSION, "run_id": run_id}
    identities = {}
    for item in sanitized:
        identity = {"version": "discovery.v1", "producer_namespace": PRODUCER, "original_run_id": run_id,
                    "source_artifact_sha256": source_hash, "source_record_key": item["source_record_key"]}
        identities[canonical(item["source_record_key"])] = (identity, digest(DOMAIN_CANDIDATE, identity))
    duplicate_edges = {}
    for item in sanitized:
        if item["outcome"] == "duplicate":
            source = canonical(item["source_record_key"])
            target = canonical(item["duplicate_target"])
            require(target in identities and target != source, "unknown or self duplicate target")
            duplicate_edges[source] = target
    visiting, visited = set(), set()
    def visit(source):
        require(source not in visiting, "duplicate cycle")
        if source in visited:
            return
        visiting.add(source)
        if source in duplicate_edges:
            visit(duplicate_edges[source])
        visiting.remove(source)
        visited.add(source)
    for source in identities:
        visit(source)
    records = []
    for item in sanitized:
        identity, cid = identities[canonical(item["source_record_key"])]
        discovered_base = base_record(producer, attr, inventory["observed_at"], item["evidence_status"])
        discovered = candidate_event(discovered_base, cid, identity, item, "discovered", 0, None)
        records.append(discovered)
        outcome_base = base_record(producer, attr, inventory["observed_at"], item["evidence_status"])
        outcome = candidate_event(outcome_base, cid, identity, item, item["outcome"], 1, discovered["event_id"])
        if item["outcome"] == "duplicate":
            target = identities.get(canonical(item["duplicate_target"]))
            require(target is not None and target[1] != cid, "unknown or self duplicate target")
            outcome["duplicate_target"] = target[1]
            seal(outcome)
        records.append(outcome)
    malformed = None if raw is None else raw - len(sanitized)
    terminal = None if raw is None else sum(item["outcome"] != "incomplete" for item in sanitized)
    incomplete = None if raw is None else len(sanitized) - terminal + malformed
    summary = base_record(producer, attr, inventory["observed_at"], {"complete": "complete", "partial": "incomplete", "unknown": "unknown"}[capture])
    summary.update({"record_type": "run_summary", "stage": "discovery", "capture_status": capture,
                    "detector_completed": inventory["detector_completed"],
                    "detector_evidence_sha256": None if capture == "unknown" else source_hash,
                    "counts": {"raw_candidates": raw, "emitted_candidates": None if raw is None else len(sanitized),
                               "terminal_stage": terminal, "incomplete": incomplete, "malformed": malformed},
                    "emission_gap_reason": "unknown" if raw is None else ("malformed" if malformed else "none")})
    records.append(seal(summary))
    validate_output(records, config)
    return records


def write_artifacts(generation_path, records):
    """Publish a complete artifact generation through one atomic directory rename."""
    generation = Path(generation_path)
    generation.parent.mkdir(parents=True, exist_ok=True)
    require(not generation.exists(), "refusing to overwrite an existing artifact generation")
    temporary = Path(tempfile.mkdtemp(prefix=".finding-observations.", suffix=".tmp",
                                      dir=generation.parent))
    try:
        for name, values in (("finding-observations.v1.summary.json", [records[-1]]),
                             ("finding-observations.v1.jsonl", records)):
            target = temporary / name
            fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_EXCL,
                         stat.S_IRUSR | stat.S_IWUSR)
            with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as handle:
                for record in values:
                    handle.write(canonical(record).decode() + "\n")
                handle.flush()
                os.fsync(handle.fileno())
        directory_fd = os.open(temporary, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
        # The generation is invisible at its canonical path until both files are
        # durable. This rename is the sole publication commit point.
        os.replace(temporary, generation)
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--generation-dir", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--schema", required=True)
    parser.add_argument("--program-id", default="unknown")
    parser.add_argument("--issue-id", default="unknown")
    parser.add_argument("--harness-run-id", required=True)
    parser.add_argument("--attempt", type=int, default=1)
    args = parser.parse_args()
    require(1 <= args.attempt <= MAX_INT, "invalid attempt")
    records = build(args)
    write_artifacts(args.generation_dir, records)


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, ValueError, TypeError, json.JSONDecodeError) as error:
        print(f"finding observation producer: {error}", file=os.sys.stderr)
        raise SystemExit(1)
