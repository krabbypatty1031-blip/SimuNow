import copy
import json
import unittest
from uuid import uuid4

from simunow_worker.models.consumer_evidence import decode


def dataset():
    return {'datasetVersion': 1, 'owner': 'com.simunow.measurements', 'id': str(uuid4()),
            'projectID': str(uuid4()), 'sourceSHA256': 'a' * 64, 'coordinateSystem': 'rightHandedZUp',
            'issues': [], 'records': [{'id': str(uuid4()), 'timestamp': '2026-10-03T15:00:00+08:00',
                'quantity': 'temperature', 'value': 25, 'unit': 'degC', 'instrument': 'synthetic meter',
                'quality': 'valid', 'fanSetting': 'unknown', 'doorState': 'unknown',
                'windowState': 'unknown', 'partition': 'unassigned'}]}


class ConsumerEvidenceTests(unittest.TestCase):
    def test_measurement_missing_remains_missing(self):
        value = dataset()
        value['records'][0].update(value=None, quality='missing', qualityReason='no reading')
        self.assertIsNone(decode('measurement-dataset', json.dumps(value))['records'][0]['value'])

    def test_measurement_refusals(self):
        base = dataset()
        for key, value in [('unit', 'W'), ('timestamp', '2026-02-30T15:00:00Z'), ('timestamp', '2026-10-03T15:00:00'),
                           ('value', None), ('instrument', ' '), ('quality', 'suspect')]:
            with self.subTest(key=key, value=value):
                altered = copy.deepcopy(base); altered['records'][0][key] = value
                with self.assertRaises(Exception): decode('measurement-dataset', json.dumps(altered))

    def test_duplicate_identity_and_keys_rejected(self):
        value = dataset(); value['records'].append(copy.deepcopy(value['records'][0]))
        with self.assertRaises(ValueError): decode('measurement-dataset', json.dumps(value))
        text = json.dumps(dataset()).replace('"datasetVersion": 1', '"datasetVersion": 1, "datasetVersion": 1')
        with self.assertRaises(ValueError): decode('measurement-dataset', text)

    def test_nonfinite_and_budget_rejected(self):
        for number in ('NaN', 'Infinity', '1e309'):
            text = json.dumps(dataset()).replace('"value": 25', '"value": ' + number)
            with self.subTest(number=number), self.assertRaises(ValueError): decode('measurement-dataset', text)
        with self.assertRaises(ValueError): decode('measurement-dataset', ' ' * (8 * 1024 * 1024 + 1))

    def test_optional_review_future_and_unknown_keys_rejected(self):
        value = {'configurationVersion': 1, 'endpoint': 'https://review.example.invalid',
                 'expectedEngine': 'fixture', 'expectedVersion': '1', 'retentionPolicy': 'none', 'maximumResponseBytes': 4096}
        self.assertEqual(decode('professional-review-configuration', json.dumps(value)), value)
        for key, bad in [('configurationVersion', 2), ('secretToken', 'never persisted'), ('maximumResponseBytes', 2097153)]:
            mutated = copy.deepcopy(value); mutated[key] = bad
            with self.subTest(key=key), self.assertRaises(Exception): decode('professional-review-configuration', json.dumps(mutated))
