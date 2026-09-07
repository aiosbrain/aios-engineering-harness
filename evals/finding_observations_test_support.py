"""Test-only reference oracle. No producer, transport, or persistence API."""
import hashlib
import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).parent
SCHEMA = json.loads((ROOT / 'schemas/finding-observations.v1.schema.json').read_text())
VALIDATOR = Draft202012Validator(SCHEMA, format_checker=FormatChecker())
TRANSITIONS = {
    'discovered': {'verified', 'duplicate', 'rejected', 'incomplete'},
    'verified': {'filed', 'duplicate', 'rejected', 'incomplete'},
    'filed': {'queue_eligible', 'duplicate', 'rejected', 'incomplete'},
    'queue_eligible': {'selected', 'duplicate', 'rejected', 'incomplete'},
    'selected': {'remediation_started', 'duplicate', 'rejected', 'incomplete'},
    'remediation_started': {'merged', 'duplicate', 'rejected', 'incomplete'},
    'merged': {'resolved', 'incomplete'},
    'resolved': {'escaped', 'reopened'},
    'escaped': {'reopened', 'incomplete'},
    'duplicate': {'reopened'},
    'rejected': {'reopened'},
    'incomplete': {'reopened'},
    'reopened': {'verified', 'duplicate', 'rejected', 'incomplete'},
}
TERMINAL = {
    'discovery': {'verified', 'filed', 'queue_eligible', 'selected',
                  'remediation_started', 'merged', 'resolved', 'duplicate', 'rejected'},
    'filing': {'filed', 'queue_eligible', 'selected', 'remediation_started',
               'merged', 'resolved', 'duplicate', 'rejected'},
    'remediation': {'merged', 'resolved', 'duplicate', 'rejected'},
    'resolution': {'resolved', 'duplicate', 'rejected'},
}


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def canonical(value):
    """Sets must already be canonical: reject, never sort/strip unsafe input."""
    return json.dumps(value, sort_keys=True, separators=(',', ':'),
                      ensure_ascii=False, allow_nan=False).encode('utf-8')


def digest(domain, value):
    return hashlib.sha256(domain.encode('ascii') + b'\x00' + canonical(value)).hexdigest()


def candidate_id(identity):
    return digest('aios.finding.candidate.discovery.v1', identity)


def event_id(event):
    return digest('aios.finding.event.v1', {k: v for k, v in event.items() if k != 'event_id'})


def strict_loads(line):
    def pairs(items):
        out = {}
        for key, value in items:
            require(key not in out, 'duplicate JSON key')
            out[key] = value
        return out

    def reject_number(value):
        raise ValueError('non-integer JSON numeric token')

    return json.loads(line, object_pairs_hook=pairs, parse_float=reject_number,
                      parse_constant=reject_number)


def read_jsonl(path):
    # BOM, blank lines, duplicate keys, floats, invalid UTF-8 all fail closed.
    text = Path(path).read_bytes().decode('utf-8')
    require(text.endswith('\n') and '\r' not in text, 'invalid JSONL framing')
    return [strict_loads(line) for line in text[:-1].split('\n')]


def check_record(record, config):
    VALIDATOR.validate(record)
    datetime.strptime(record['observed_at'], '%Y-%m-%dT%H:%M:%SZ')
    # Python's JSON Schema validator treats 1.0 as an integer; wire tokens may not.
    def integers(value):
        require(not isinstance(value, float), 'float value')
        if isinstance(value, dict):
            for item in value.values():
                integers(item)
        elif isinstance(value, list):
            for item in value:
                integers(item)
    integers(record)
    producer = record['producer']
    require(producer['name'] in config['producers'], 'unconfigured producer')
    require(producer['version'] in config['producers'][producer['name']], 'unconfigured version')
    require(record['event_id'] == event_id(record), 'invalid event ID')
    attr = record['attribution']
    if attr['issue'] is not None:
        require(attr['issue']['team'] in config['linear_teams'], 'unconfigured Linear team')
    if record['record_type'] == 'run_summary':
        return
    identity = record['identity']
    require(identity['producer_namespace'] == producer['name'], 'producer namespace mismatch')
    require(record['candidate_id'] == candidate_id(identity), 'invalid candidate ID')
    for field, values in [('codebases', record['codebases']),
                          ('fences', record['taxonomy']['fences'])]:
        require(values == sorted(set(values)), 'noncanonical ' + field)
    require(set(record['codebases']) <= set(config['codebases']), 'unconfigured codebase')
    require('cross-repo' not in record['codebases'], 'cross-repo is not a membership')
    fences = record['taxonomy']['fences']
    require(not ({'none', 'unknown'} & set(fences)) or len(fences) == 1, 'exclusive fence')
    links = record['links']
    if links['linear'] is not None:
        require(links['linear']['team'] in config['linear_teams'], 'unconfigured Linear team')
    if links['scanner'] is not None:
        require(links['scanner']['producer'] in config['producers'], 'unconfigured scanner')
    for key in ['pull_request', 'merge']:
        if links[key] is not None:
            require(links[key]['codebase'] in record['codebases'], 'link outside memberships')
    state = record['state']
    disposition = {'duplicate': 'duplicate', 'rejected': 'rejected',
                   'resolved': 'resolved', 'incomplete': 'unknown'}.get(state, 'open')
    require(record['disposition'] == disposition, 'contradictory disposition')
    require((record['duplicate_target'] is not None) == (state == 'duplicate'), 'duplicate linkage')
    if state not in {'discovered', 'incomplete'}:
        require(record['evidence_status'] == 'complete', 'transition lacks evidence')
    if state == 'incomplete':
        require(record['evidence_status'] != 'complete', 'incomplete claims complete evidence')
    if state in {'filed', 'queue_eligible', 'selected', 'remediation_started', 'merged', 'resolved'}:
        require(links['linear'] is not None or links['scanner'] is not None, 'filing link missing')
    if state in {'merged', 'resolved'}:
        require(links['merge'] is not None, 'merge link missing')
    if state == 'resolved':
        require(links['resolution'] is not None, 'resolution evidence missing')


def validate(records, config):
    """Validate a complete ledger (including prior-run history); deduplicate exact replay."""
    unique = {}
    for record in records:
        check_record(record, config)
        key = record['event_id']
        require(key not in unique or unique[key] == record, 'conflicting event replay')
        unique[key] = record
    histories = defaultdict(list)
    summaries = {}
    run_candidates = defaultdict(dict)
    run_attrs = {}
    for record in unique.values():
        run = (record['producer']['name'], record['producer']['run_id'])
        require(run not in run_attrs or run_attrs[run] == record['attribution'], 'run attribution conflict')
        run_attrs[run] = record['attribution']
        if record['record_type'] == 'candidate':
            histories[record['candidate_id']].append(record)
            cid = record['candidate_id']
            old = run_candidates[run].get(cid)
            if old is None or old['sequence'] < record['sequence']:
                run_candidates[run][cid] = record
        else:
            require(run not in summaries, 'conflicting run summaries')
            summaries[run] = record
    duplicate_edges = defaultdict(set)
    for cid, events in histories.items():
        events.sort(key=lambda e: e['sequence'])
        first = events[0]
        require(first['state'] == 'discovered' and first['episode'] == 0, 'missing discovery')
        require(first['producer']['run_id'] == first['identity']['original_run_id'], 'discovery run mismatch')
        previous = None
        for sequence, event in enumerate(events):
            require(event['sequence'] == sequence, 'sequence conflict or gap')
            require(event['identity'] == first['identity'], 'conflicting discovery identity')
            require(event['attribution']['program_id'] == first['attribution']['program_id'], 'program changed')
            require(event['predecessor_event_id'] == (previous['event_id'] if previous else None),
                    'invalid predecessor')
            if previous:
                require(event['state'] in TRANSITIONS[previous['state']], 'invalid transition')
                require(event['episode'] == previous['episode'] + (event['state'] == 'reopened'),
                        'invalid lifecycle episode')
            if event['state'] == 'duplicate':
                target = event['duplicate_target']
                require(target != cid and target in histories, 'unknown or self duplicate target')
                duplicate_edges[cid].add(target)
            previous = event
    # Check historical edges too: reopening does not erase duplicate evidence.
    visiting, visited = set(), set()
    def visit(cid):
        require(cid not in visiting, 'duplicate cycle')
        if cid in visited:
            return
        visiting.add(cid)
        for target in duplicate_edges.get(cid, ()):
            visit(target)
        visiting.remove(cid)
        visited.add(cid)
    for cid in histories:
        visit(cid)
    require(bool(summaries), 'missing finalized summary')
    require(set(run_candidates) <= set(summaries), 'missing finalized summary')
    for run, summary in summaries.items():
        counts = summary['counts']
        candidates = run_candidates.get(run, {})
        capture = summary['capture_status']
        if capture == 'unknown':
            require(all(v is None for v in counts.values()), 'unknown capture has counts')
            require(summary['detector_completed'] is None and summary['detector_evidence_sha256'] is None,
                    'unknown capture claims completion')
            require(summary['evidence_status'] == 'unknown' and summary['emission_gap_reason'] == 'unknown',
                    'unknown capture status mismatch')
            continue
        require(all(v is not None for v in counts.values()), 'known capture lacks counts')
        require(summary['detector_completed'] is (capture == 'complete'), 'detector status mismatch')
        require(summary['detector_evidence_sha256'] is not None, 'detector evidence missing')
        require(summary['evidence_status'] == ('complete' if capture == 'complete' else 'incomplete'),
                'capture evidence mismatch')
        raw, emitted, terminal, incomplete, malformed = (
            counts[k] for k in ['raw_candidates', 'emitted_candidates', 'terminal_stage', 'incomplete', 'malformed'])
        require(raw == terminal + incomplete, 'raw denominator mismatch')
        require(emitted == len(candidates), 'emitted denominator mismatch')
        require(raw - emitted == malformed and malformed <= incomplete, 'malformed gap mismatch')
        require(summary['emission_gap_reason'] == ('malformed' if malformed else 'none'), 'gap reason mismatch')
        expected_terminal = sum(e['state'] in TERMINAL[summary['stage']] for e in candidates.values())
        require(terminal == expected_terminal, 'terminal count mismatch')
        require(incomplete == emitted - expected_terminal + malformed, 'incomplete count mismatch')
        require(raw != 0 or capture == 'complete', 'empty capture lacks detector completion')
    return {'candidates': len(histories), 'events': len(unique), 'summaries': len(summaries)}
