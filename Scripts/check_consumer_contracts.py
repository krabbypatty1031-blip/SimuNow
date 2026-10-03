#!/usr/bin/env python3
"""Independent JSON Schema validation of actual Swift N5/N6 records and refusal examples."""
import copy
import json
from pathlib import Path
import sys
from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Backend/src'))
from simunow_worker.models.consumer_evidence import decode, verify_calibration_parent


def main(directory):
    count = 0
    for name in ('comparison-record', 'measurement-dataset', 'jet-calibration', 'professional-review-configuration', 'professional-review-receipt', 'redacted-report', 'redacted-measurements'):
        schema = json.loads((ROOT / 'Protocols/Schemas' / f'{name}.schema.json').read_text())
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        value = json.loads((directory / f'{name}.json').read_text())
        validator.validate(value)
        decode(name, (directory / f'{name}.json').read_bytes())
        mutations = []
        wrong_version = copy.deepcopy(value)
        key = {'comparison-record': 'recordVersion', 'measurement-dataset': 'datasetVersion', 'jet-calibration': 'calibrationVersion', 'professional-review-configuration': 'configurationVersion', 'professional-review-receipt': 'receiptVersion', 'redacted-report': 'exportVersion', 'redacted-measurements': 'exportVersion'}[name]
        wrong_version[key] = 2
        mutations.append(wrong_version)
        extra_field = copy.deepcopy(value)
        extra_field['unexpectedField'] = True
        mutations.append(extra_field)
        if name == 'comparison-record':
            missing_parent = copy.deepcopy(value)
            missing_parent['references'][0].pop('inputSHA256')
            mutations.append(missing_parent)
        if name == 'measurement-dataset':
            missing_timezone = copy.deepcopy(value)
            missing_timezone['records'][0]['timestamp'] = '2026-10-03T15:00:00'
            mutations.append(missing_timezone)
            wrong_unit = copy.deepcopy(value)
            wrong_unit['records'][0]['unit'] = 'W' if wrong_unit['records'][0]['quantity'] != 'electricalPower' else 'm/s'
            mutations.append(wrong_unit)
        for mutated in mutations:
            if not list(validator.iter_errors(mutated)):
                raise AssertionError(f'{name} accepted refusal fixture')
            count += 1
    verify_calibration_parent((directory / 'jet-calibration.json').read_bytes(), (directory / 'jet-calibration-dataset.json').read_bytes())
    print(f'N5/N6: 8 real Swift records (including the measured calibration parent) and {count} refusal fixtures passed independent Python schemas.')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
