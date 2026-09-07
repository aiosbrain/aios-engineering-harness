#!/usr/bin/env python3
"""Executable finding-observations v1 conformance; development-only jsonschema."""
import copy
import json
import random
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

try:
    import jsonschema
except ImportError:
    print('SKIPPED: finding observation conformance requires development-only jsonschema', file=sys.stderr)
    sys.exit(77)

from finding_observations_test_support import (
    SCHEMA, canonical, candidate_id, event_id, read_jsonl, strict_loads, validate,
)

FIXTURES = Path(__file__).parent / 'fixtures/finding-observations.v1'
CONFIG = json.loads((FIXTURES / 'trusted-config.json').read_text())


def fixture(name):
    return read_jsonl(FIXTURES / 'positive' / (name + '.jsonl'))


def reseal(events):
    previous = {}
    for event in events:
        if event['record_type'] == 'candidate':
            cid = event['candidate_id']
            if event['sequence']:
                event['predecessor_event_id'] = previous[cid]
            event['event_id'] = event_id(event)
            previous[cid] = event['event_id']
        else:
            event['event_id'] = event_id(event)
    return events


class FindingContractTests(unittest.TestCase):
    def assert_invalid(self, events):
        with self.assertRaises((ValueError, jsonschema.ValidationError)):
            validate(events, CONFIG)

    def test_schema_and_positive_fixtures(self):
        jsonschema.Draft202012Validator.check_schema(SCHEMA)
        paths = sorted((FIXTURES / 'positive').glob('*.jsonl'))
        self.assertGreaterEqual(len(paths), 8)
        for path in paths:
            with self.subTest(path=path.name):
                validate(read_jsonl(path), CONFIG)

    def test_negative_fixtures(self):
        paths = sorted((FIXTURES / 'negative').glob('*.jsonl'))
        self.assertGreaterEqual(len(paths), 30)
        for path in paths:
            with self.subTest(path=path.name):
                with self.assertRaises((ValueError, jsonschema.ValidationError)):
                    validate(read_jsonl(path), CONFIG)

    def test_known_answers(self):
        answers = json.loads((FIXTURES / 'known-answers.json').read_text())
        event = fixture('complete-lifecycle')[0]
        self.assertEqual(canonical(answers['identity']).decode(), answers['canonical_identity_utf8'])
        self.assertEqual(candidate_id(answers['identity']), answers['candidate_id'])
        self.assertEqual(event_id(event), answers['discovered_event_id'])
        self.assertEqual(event['candidate_id'], answers['candidate_id'])
        # Independent SHA implementation verifies domain separator and exact UTF-8 bytes.
        result = subprocess.run(['shasum', '-a', '256'], input=(
            b'aios.finding.candidate.discovery.v1\x00' + answers['canonical_identity_utf8'].encode()),
            capture_output=True, check=True)
        self.assertEqual(result.stdout.decode().split()[0], answers['candidate_id'])

    def test_independent_order_and_exact_replay(self):
        events = fixture('five-candidate-worked-example')
        expected = validate(events, CONFIG)
        shuffled = copy.deepcopy(events)
        random.Random(1098).shuffle(shuffled)
        self.assertEqual(validate(shuffled, CONFIG), expected)
        self.assertEqual(validate(events + shuffled + events, CONFIG), expected)
        self.assertEqual(expected, {'candidates': 5, 'events': 11, 'summaries': 1})
        # JSON object insertion order does not change IDs either.
        reordered = strict_loads(json.dumps(events[0], sort_keys=False))
        reordered = dict(reversed(list(reordered.items())))
        self.assertEqual(event_id(reordered), events[0]['event_id'])

    def test_five_candidate_reconciliation(self):
        events = fixture('five-candidate-worked-example')
        latest = {e['candidate_id']: e for e in events if e['record_type'] == 'candidate'}
        self.assertCountEqual([e['state'] for e in latest.values()],
                              ['verified', 'duplicate', 'rejected', 'verified', 'incomplete'])
        self.assertEqual(events[-1]['counts'], dict(raw_candidates=5, emitted_candidates=5,
                                                  terminal_stage=4, incomplete=1, malformed=0))
        dup = next(e for e in latest.values() if e['state'] == 'duplicate')
        self.assertNotEqual(dup['candidate_id'], dup['duplicate_target'])
        self.assertIn(dup['duplicate_target'], latest)
        cross = next(e for e in latest.values() if len(e['codebases']) == 2)
        self.assertEqual(cross['codebases'], ['devtools', 'harness'])
        self.assertTrue(all(v is None for v in cross['links'].values()))

    def test_identity_freezes_across_software_and_lifecycle_runs(self):
        events = fixture('escaped-reopened')
        candidates = [e for e in events if e['record_type'] == 'candidate']
        self.assertEqual(len({e['candidate_id'] for e in candidates}), 1)
        self.assertEqual(len({e['producer']['version'] for e in candidates}), 2)
        self.assertEqual(validate(events, CONFIG)['summaries'], 2)
        changed = copy.deepcopy(candidates[0]['identity'])
        for key, value in [('original_run_id', 'e' * 64), ('source_artifact_sha256', 'd' * 64),
                           ('source_record_key', {'kind': 'position', 'value': 999}),
                           ('producer_namespace', 'scanner')]:
            other = {**changed, key: value}
            self.assertNotEqual(candidate_id(other), candidates[0]['candidate_id'])

    def test_no_timestamp_ordering(self):
        events = fixture('complete-lifecycle')
        for event in events:
            if event.get('sequence', 0) > 0:
                event['observed_at'] = '2020-01-01T00:00:00Z'
        validate(reseal(events), CONFIG)

    def test_unknown_states_and_fences(self):
        events = fixture('five-candidate-worked-example')
        events[0]['taxonomy'] = dict(severity='unknown', defect_class='unknown',
                                    determinism='unknown', fences=['unknown'])
        validate(reseal(events), CONFIG)
        events[0]['taxonomy']['fences'] = ['schema', 'unknown']
        self.assert_invalid(reseal(events))

    def test_recursive_unknown_keys_and_unsafe_channels(self):
        original = fixture('five-candidate-worked-example')
        # Every object node rejects added content, including typed nullable link variants.
        def paths(value, prefix=()):
            if isinstance(value, dict):
                yield prefix
                for key, item in value.items():
                    yield from paths(item, prefix + (key,))
        for path in paths(original[0]):
            for forbidden in ['path', 'excerpt', 'patch', 'prompt', 'transcript', 'credential', 'contributor']:
                with self.subTest(path=path, forbidden=forbidden):
                    events = copy.deepcopy(original)
                    target = events[0]
                    for key in path:
                        target = target[key]
                    target[forbidden] = 'synthetic disallowed content'
                    self.assert_invalid(reseal(events))
        for key, link in {
            'linear': {'type': 'linear', 'team': 'AIO', 'number': 12},
            'scanner': {'type': 'scanner', 'producer': 'scanner', 'finding_id': 'a'*64},
            'pull_request': {'type': 'pull_request', 'codebase': 'harness', 'number': 12},
            'merge': {'type': 'merge', 'codebase': 'harness', 'sha': 'a'*40},
            'resolution': {'type': 'resolution', 'sha256': 'a'*64},
        }.items():
            events = copy.deepcopy(original)
            events[0]['links'][key] = link
            validate(reseal(events), CONFIG)
            link['url'] = 'https://example.invalid/private'
            self.assert_invalid(reseal(events))

    def test_identifier_values_and_numeric_bounds(self):
        for value in ['src/private.py', 'hello world', 'https://example.invalid', '../harness',
                      'harness\n', 'alice@example.invalid', 'A'*64]:
            events = fixture('five-candidate-worked-example')
            events[0]['producer']['name'] = value
            self.assert_invalid(reseal(events))
        for value in [-1, 2147483648, 1.0, True, None, '1']:
            events = fixture('five-candidate-worked-example')
            events[0]['attribution']['attempt'] = value
            self.assert_invalid(reseal(events))

    def test_missing_and_conflicting_history(self):
        events = fixture('complete-lifecycle')
        self.assert_invalid(events[:-1])
        events[1]['predecessor_event_id'] = '0'*64
        events[1]['event_id'] = event_id(events[1])
        self.assert_invalid(events)
        events = fixture('complete-lifecycle')
        events.insert(2, {**events[1], 'taxonomy': {**events[1]['taxonomy'], 'severity': 'high'}})
        self.assert_invalid(reseal(events))

    def test_capture_denominator_and_stage_are_distinct(self):
        failure, empty = fixture('provider-failure'), fixture('empty-success')
        validate(failure, CONFIG)
        validate(empty, CONFIG)
        self.assertIsNone(failure[0]['counts']['raw_candidates'])
        self.assertEqual(empty[0]['counts']['raw_candidates'], 0)
        events = fixture('five-candidate-worked-example')
        events[-1]['stage'] = 'filing'
        self.assert_invalid(reseal(events))
        events[-1]['counts'].update(terminal_stage=2, incomplete=3)
        validate(reseal(events), CONFIG)

    def test_strict_jsonl_framing(self):
        source = (FIXTURES / 'positive/five-candidate-worked-example.jsonl').read_bytes()
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'records.jsonl'
            for separator in ['\r\n', '\r', '\u0085', '\u2028', '\u2029', '\f', '\v']:
                path.write_bytes(source.replace(b'\n', separator.encode('utf-8')))
                with self.subTest(separator=repr(separator)), self.assertRaises(ValueError):
                    read_jsonl(path)
            for content in [b'', source.rstrip(b'\n'), source + b'\n', b'\xff\n']:
                path.write_bytes(content)
                with self.assertRaises(ValueError):
                    read_jsonl(path)
        self.assert_invalid([])

    def test_strict_json_parser(self):
        for text in ['{"a":1,"a":2}', '{"a":{"b":1,"b":2}}', '{"n":NaN}',
                     '{"n":Infinity}', '{"n":1.0}', '{"n":1e0}', '', '\ufeff{}']:
            with self.subTest(text=text), self.assertRaises(ValueError):
                strict_loads(text)


if __name__ == '__main__':
    unittest.main()
