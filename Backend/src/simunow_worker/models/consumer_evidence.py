"""Strict optional N5/N6 wire parsing, for development interoperability only.

This boundary does not fit a model or turn a stored acceptance flag into physical validation.
Hash and fixed-parent validation in the native app remain authoritative.
"""
from datetime import datetime
from functools import lru_cache
import hashlib
import json
import math
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

SCHEMAS = Path(__file__).resolve().parents[4] / 'Protocols' / 'Schemas'
KINDS = frozenset(('comparison-record', 'measurement-dataset', 'jet-calibration',
                   'professional-review-configuration', 'professional-review-receipt', 'redacted-report', 'redacted-measurements', 'room-capture'))


def _object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('duplicate JSON key')
        result[key] = value
    return result


def _nonfinite(_):
    raise ValueError('non-finite JSON number')


@lru_cache(maxsize=8)
def _validator(kind):
    if kind not in KINDS:
        raise ValueError('unknown consumer wire kind')
    schema = json.loads((SCHEMAS / f'{kind}.schema.json').read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def decode(kind, data):
    limit = 8 * 1024 * 1024 if kind == 'measurement-dataset' else 256 * 1024
    if len(data.encode('utf-8') if isinstance(data, str) else data) > limit:
        raise ValueError('consumer wire byte budget')
    value = json.loads(data, object_pairs_hook=_object, parse_constant=_nonfinite)
    def finite(node):
        if isinstance(node, float) and not math.isfinite(node):
            raise ValueError('non-finite JSON number')
        if isinstance(node, dict):
            for item in node.values(): finite(item)
        elif isinstance(node, list):
            for item in node: finite(item)
    finite(value)
    _validator(kind).validate(value)
    if kind == 'measurement-dataset':
        identifiers = [row['id'].lower() for row in value['records']]
        if len(set(identifiers)) != len(identifiers):
            raise ValueError('duplicate measurement identity')
        for row in value['records']:
            # Python's parser rejects invalid days; the schema requires an explicit timezone.
            moment = datetime.fromisoformat(row['timestamp'].replace('Z', '+00:00'))
            if moment.tzinfo is None or not row['instrument'].strip() or not row['fanSetting'].strip():
                raise ValueError('missing measurement source or timezone')
            if row['quality'] != 'valid' and not row.get('qualityReason', ''):
                raise ValueError('quality reason required')
            if row['quality'] == 'valid' and row.get('value') is None:
                raise ValueError('valid measurement has no reading')
            if row['quality'] == 'missing' and row.get('value') is not None:
                raise ValueError('missing reading must remain null')
    elif kind == 'comparison-record':
        runs = value['snapshot']['runs']
        if runs != [reference['run'] for reference in value['references']]:
            raise ValueError('comparison parents differ from snapshot')
        if len({run['runID'].lower() for run in runs}) != len(runs) or len({run['scenarioID'].lower() for run in runs}) != len(runs):
            raise ValueError('duplicate comparison identity')
    elif kind == 'jet-calibration':
        training, holdout = value['calibrationIDs'], value['validationIDs']
        if len(set(training)) != len(training) or len(set(holdout)) != len(holdout) or set(training) & set(holdout):
            raise ValueError('calibration identity leakage')
        if value['calibrationMetrics']['sampleCount'] != len(training) or value['validationMetrics']['sampleCount'] != len(holdout):
            raise ValueError('calibration sample count mismatch')
        if value['minimumDistanceMeters'] > value['maximumDistanceMeters']:
            raise ValueError('invalid measured range')
    elif kind in ('redacted-report', 'redacted-measurements'):
        from .json_value import Number, parse
        def canonical(node):
            if isinstance(node, Number): return node.token
            if isinstance(node, dict):
                return '{' + ','.join(json.dumps(key, ensure_ascii=False) + ':' + canonical(item) for key, item in sorted(node.items())) + '}'
            if isinstance(node, list): return '[' + ','.join(map(canonical, node)) + ']'
            return json.dumps(node, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
        tree = parse(data)
        if hashlib.sha256(canonical(tree['snapshot']).encode()).hexdigest() != value['exportHash']:
            raise ValueError('redacted export hash mismatch')
    return value


def verify_calibration_parent(record_bytes, dataset_bytes):
    record = decode('jet-calibration', record_bytes)
    dataset = decode('measurement-dataset', dataset_bytes)
    if record['datasetID'] != dataset['id'] or record['projectID'] != dataset['projectID'] or record['datasetSHA256'] != hashlib.sha256(dataset_bytes).hexdigest():
        raise ValueError('calibration parent mismatch')
    rows = {row['id']: row for row in dataset['records']}
    for partition, ids in [('calibration', record['calibrationIDs']), ('validation', record['validationIDs'])]:
        if any(key not in rows or rows[key]['partition'] != partition or rows[key]['quality'] != 'valid'
               or rows[key]['quantity'] != 'airSpeed' or rows[key].get('deviceID') != record['deviceID'] for key in ids):
            raise ValueError('calibration referenced measurement mismatch')
    return record  # Does not authorize quantitative prediction; Swift must rebuild the fit.
