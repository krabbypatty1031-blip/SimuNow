#!/usr/bin/env python3
"""Strict N5/N6 sidefile and optional-node wire schemas; no app runtime dependency."""
import argparse
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def generate(check=False):
    comparison = json.loads((ROOT / 'Protocols/Schemas/comparison-snapshot.schema.json').read_text())
    definitions = copy.deepcopy(comparison['$defs'])
    snapshot = {key: value for key, value in comparison.items() if key not in ('$schema', '$id', '$defs', 'title')}
    definitions['FixedComparisonSnapshot'] = snapshot
    hash_value = {'type': 'string', 'pattern': '^[a-f0-9]{64}$'}
    schema = {
        '$schema': 'https://json-schema.org/draft/2020-12/schema',
        '$id': 'https://simunow.local/schemas/comparison-record.schema.json',
        'type': 'object', 'additionalProperties': False,
        'required': ['recordVersion', 'owner', 'snapshot', 'references', 'bodyHash'],
        'properties': {
            'recordVersion': {'const': 1}, 'owner': {'const': 'com.simunow.comparison'},
            'snapshot': {'$ref': '#/$defs/FixedComparisonSnapshot'},
            'references': {'type': 'array', 'minItems': 2, 'maxItems': 3, 'items': {
                'type': 'object', 'additionalProperties': False,
                'required': ['run', 'inputSHA256', 'resultSHA256'],
                'properties': {'run': {'$ref': '#/$defs/ComparisonRunReference'},
                               'inputSHA256': hash_value, 'resultSHA256': hash_value}}},
            'bodyHash': hash_value}, '$defs': definitions}
    data = json.dumps(schema, ensure_ascii=False, indent=2) + '\n'
    for directory in ('Protocols/Schemas', 'Packages/SimuKit/Sources/SimuCore/Resources'):
        path = ROOT / directory / 'comparison-record.schema.json'
        if check:
            if not path.exists() or path.read_text() != data:
                raise SystemExit(f'Schema drift: {path}')
        else:
            path.write_text(data)
    def object_schema(properties, required=None):
        return {'type': 'object', 'additionalProperties': False, 'properties': properties,
                'required': required if required is not None else list(properties)}
    string = {'type': 'string', 'minLength': 1, 'maxLength': 4096}
    uuid = {'type': 'string', 'format': 'uuid'}
    def nullable(value):
        return {'anyOf': [value, {'type': 'null'}]}
    position = object_schema({key: {'type': 'number'} for key in ('x', 'y', 'z')})
    record_properties = {
        'id': uuid, 'timestamp': {**string, 'pattern': '^[0-9]{4}-[0-9]{2}-[0-9]{2}T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\\.[0-9]+)?(Z|[+-]([01][0-9]|2[0-3]):[0-5][0-9])$'},
        'position': nullable(position),
        'quantity': {'enum': ['airSpeed', 'outletSpeed', 'outletFlow', 'temperature', 'electricalPower', 'relativeHumidity', 'co2']},
        'value': nullable({'type': 'number'}), 'unit': {'enum': ['m/s', 'm3/s', 'degC', 'W', '%', 'ppm']},
        'instrument': string, 'instrumentRange': nullable(string), 'instrumentCalibration': nullable(string),
        'quality': {'enum': ['valid', 'suspect', 'missing', 'rejected']}, 'qualityReason': nullable(string),
        'fanSetting': string, 'doorState': {'enum': ['open', 'closed', 'unknown']},
        'windowState': {'enum': ['open', 'closed', 'unknown']},
        'partition': {'enum': ['calibration', 'validation', 'unassigned']}, 'deviceID': nullable(uuid)}
    optional = {'position', 'value', 'instrumentRange', 'instrumentCalibration', 'qualityReason', 'deviceID'}
    dataset = object_schema({
        'datasetVersion': {'const': 1}, 'owner': {'const': 'com.simunow.measurements'}, 'id': uuid,
        'projectID': uuid, 'sourceSHA256': hash_value, 'coordinateSystem': {'const': 'rightHandedZUp'},
        'records': {'type': 'array', 'maxItems': 10000, 'items': object_schema(record_properties, [key for key in record_properties if key not in optional])},
        'issues': {'type': 'array', 'maxItems': 10000, 'items': object_schema({'row': {'type': 'integer', 'minimum': 1}, 'code': string, 'message': string})}})
    dataset['properties']['records']['items']['allOf'] = [
        {'if': {'properties': {'quantity': {'const': quantity}}, 'required': ['quantity']},
         'then': {'properties': {'unit': {'const': unit}, 'value': nullable({'type': 'number', 'minimum': minimum, **({'maximum': 100} if quantity == 'relativeHumidity' else {})})}}}
        for quantity, unit, minimum in [('airSpeed', 'm/s', 0), ('outletSpeed', 'm/s', 0), ('outletFlow', 'm3/s', 0),
                                        ('temperature', 'degC', -273.15), ('electricalPower', 'W', 0), ('relativeHumidity', '%', 0), ('co2', 'ppm', 0)]
    ]
    dataset['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
    dataset['$id'] = 'https://simunow.local/schemas/measurement-dataset.schema.json'
    measurement_data = json.dumps(dataset, ensure_ascii=False, indent=2) + '\n'
    for directory in ('Protocols/Schemas', 'Packages/SimuKit/Sources/SimuCore/Resources'):
        path = ROOT / directory / 'measurement-dataset.schema.json'
        if check:
            if not path.exists() or path.read_text() != measurement_data:
                raise SystemExit(f'Schema drift: {path}')
        else:
            path.write_text(measurement_data)
    metrics = object_schema({'sampleCount': {'type': 'integer', 'minimum': 1, 'maximum': 2000},
        **{key: {'type': 'number', 'minimum': 0} for key in ('meanAbsoluteErrorMetersPerSecond', 'rootMeanSquaredErrorMetersPerSecond', 'maximumAbsoluteErrorMetersPerSecond')}})
    calibration = object_schema({
        'calibrationVersion': {'const': 1}, 'method': {'const': 'simunow.experimental.finiteJet.v1'},
        **{key: uuid for key in ('id', 'projectID', 'datasetID', 'deviceID')},
        'datasetSHA256': hash_value, 'geometrySHA256': hash_value, 'origin': position, 'direction': position,
        **{key: {'type': 'number', 'exclusiveMinimum': 0} for key in ('outletSpeedMetersPerSecond', 'outletRadiusMeters', 'spreadingRate', 'decayRatePerMeter', 'maximumDistanceMeters', 'minimumDistanceMeters', 'maximumRadialDistanceMeters', 'maximumValidationRMSE')},
        'fanSetting': string,
        'calibrationIDs': {'type': 'array', 'minItems': 6, 'maxItems': 2000, 'items': uuid},
        'validationIDs': {'type': 'array', 'minItems': 3, 'maxItems': 2000, 'items': uuid},
        'calibrationMetrics': metrics, 'validationMetrics': metrics, 'uncalibratedValidationMetrics': metrics,
        'acceptedForScopedResearch': {'type': 'boolean'}, 'limitations': {'type': 'array', 'minItems': 1, 'maxItems': 10, 'items': string}})
    calibration['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
    calibration['$id'] = 'https://simunow.local/schemas/jet-calibration.schema.json'
    calibration_data = json.dumps(calibration, ensure_ascii=False, indent=2) + '\n'
    for directory in ('Protocols/Schemas', 'Packages/SimuKit/Sources/SimuCore/Resources'):
        path = ROOT / directory / 'jet-calibration.schema.json'
        if check:
            if not path.exists() or path.read_text() != calibration_data:
                raise SystemExit(f'Schema drift: {path}')
        else:
            path.write_text(calibration_data)

    positive_position = object_schema({key: {'type': 'number', 'exclusiveMinimum': 0} for key in ('x', 'y', 'z')})
    capture = object_schema({'captureVersion': {'const': 1}, 'captureID': uuid,
        'coordinateSystem': {'const': 'rightHandedZUp'}, 'appleOriginInDomain': position,
        'roomDimensionsMeters': positive_position,
        'furniture': {'type': 'array', 'maxItems': 128, 'items': object_schema({'origin': position, 'dimensions': positive_position})},
        'source': {'allOf': [{'$ref': '#/$defs/SourceRecord'}, {'properties': {'kind': {'const': 'scan'}}}]}})
    capture['$defs'] = definitions
    capture['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
    capture['$id'] = 'https://simunow.local/schemas/room-capture.schema.json'
    capture_data = json.dumps(capture, ensure_ascii=False, indent=2) + '\n'
    for directory in ('Protocols/Schemas', 'Packages/SimuKit/Sources/SimuCore/Resources'):
        path = ROOT / directory / 'room-capture.schema.json'
        if check:
            if not path.exists() or path.read_text() != capture_data:
                raise SystemExit(f'Schema drift: {path}')
        else:
            path.write_text(capture_data)

    report_run = object_schema({
        'reference': {'$ref': '#/$defs/ComparisonRunReference'}, 'scenarioAlias': string,
        'basis': {'enum': ['rulePreview', 'simplifiedEstimate']},
        'checks': {'const': 'passed'}, 'historical': {'type': 'boolean'},
        **{key: {'type': 'array', 'items': string} for key in ('lines', 'assumptions', 'missingReasons')}})
    report_snapshot = object_schema({'reportVersion': {'const': 1}, 'reportID': uuid,
        'createdAt': {'type': 'string', 'pattern': '^[0-9]{4}-[0-9]{2}-[0-9]{2}T.*Z$'},
        'runs': {'type': 'array', 'minItems': 1, 'maxItems': 12, 'items': report_run},
        'comparison': nullable({'$ref': '#/$defs/FixedComparisonSnapshot'}),
        'redactedFields': {'type': 'array', 'minItems': 1, 'items': string},
        'limitations': {'type': 'array', 'minItems': 1, 'items': string}},
        ['reportVersion', 'reportID', 'createdAt', 'runs', 'redactedFields', 'limitations'])
    report = object_schema({'owner': {'const': 'com.simunow.redacted-report'}, 'exportVersion': {'const': 1},
        'hashFormat': {'const': 'sha256.sorted-json.iso8601.v1'}, 'exportHash': hash_value, 'snapshot': report_snapshot})
    report['$defs'] = definitions
    summary_row = object_schema({key: record_properties[key] for key in ('quantity', 'value', 'unit', 'quality', 'partition', 'doorState', 'windowState')})
    summary_row['properties'].update({'deviceAlias': nullable(string), 'instrumentAlias': string, 'fanAlias': string})
    summary_row['required'] = ['quantity', 'unit', 'quality', 'partition', 'doorState', 'windowState', 'instrumentAlias', 'fanAlias']
    measurement_summary = object_schema({'owner': {'const': 'com.simunow.redacted-measurements'}, 'exportVersion': {'const': 1},
        'hashFormat': {'const': 'sha256.sorted-json.v1'}, 'exportHash': hash_value,
        'snapshot': object_schema({'summaryVersion': {'const': 1}, 'sourceSHA256': hash_value,
            'records': {'type': 'array', 'maxItems': 10000, 'items': summary_row},
            'rejectedRowCount': {'type': 'integer', 'minimum': 0, 'maximum': 10000},
            'redactedFields': {'type': 'array', 'minItems': 1, 'items': string},
            'limitations': {'type': 'array', 'minItems': 1, 'items': string}})})
    for name, value in [('redacted-report', report), ('redacted-measurements', measurement_summary)]:
        value['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
        value['$id'] = f'https://simunow.local/schemas/{name}.schema.json'
        data = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
        for directory in ('Protocols/Schemas', 'Packages/SimuKit/Sources/SimuCore/Resources'):
            path = ROOT / directory / f'{name}.schema.json'
            if check:
                if not path.exists() or path.read_text() != data:
                    raise SystemExit(f'Schema drift: {path}')
            else:
                path.write_text(data)

    review_configuration = object_schema({
        'configurationVersion': {'const': 1}, 'endpoint': string, 'expectedEngine': string,
        'expectedVersion': string, 'retentionPolicy': string,
        'maximumResponseBytes': {'type': 'integer', 'minimum': 1, 'maximum': 2097152}})
    review_receipt = object_schema({'receiptVersion': {'const': 1}, 'runID': uuid, 'inputHash': hash_value,
        'engine': string, 'engineVersion': string, 'qualityPassed': {'type': 'boolean'}, 'benchmarkReference': string, 'resultReference': string})
    for name, value in [('professional-review-configuration', review_configuration), ('professional-review-receipt', review_receipt)]:
        value['$schema'] = 'https://json-schema.org/draft/2020-12/schema'
        value['$id'] = f'https://simunow.local/schemas/{name}.schema.json'
        data = json.dumps(value, ensure_ascii=False, indent=2) + '\n'
        for directory in ('Protocols/Schemas', 'Packages/SimuKit/Sources/SimuCore/Resources'):
            path = ROOT / directory / f'{name}.schema.json'
            if check:
                if not path.exists() or path.read_text() != data:
                    raise SystemExit(f'Schema drift: {path}')
            else:
                path.write_text(data)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    generate(parser.parse_args().check)
