"""App-only package metadata schema; the worker does not consume packages yet."""
import json
from pathlib import Path
import unittest
from jsonschema import Draft202012Validator, FormatChecker


class PackageMetadataSchemaTests(unittest.TestCase):
    def test_version_pairs_and_unknown_fields_are_strict(self):
        path = Path(__file__).resolve().parents[2] / "Protocols/Schemas/project-package-metadata.schema.json"
        schema = json.loads(path.read_text())
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        for valid in [
            {"packageVersion": 1},
            {"packageVersion": 1, "baselineScenarioID": "00000000-0000-0000-0000-000000000001"},
            {"packageVersion": 1, "templateID": "simunow.template.office", "templateVersion": 1},
        ]:
            self.assertTrue(validator.is_valid(valid), valid)
        for invalid in [
            {}, {"packageVersion": 2}, {"packageVersion": 1, "future": True},
            {"packageVersion": 1, "templateID": "office"},
            {"packageVersion": 1, "templateVersion": 1},
            {"packageVersion": 1, "templateID": " ", "templateVersion": 1},
            {"packageVersion": 1, "templateID": "office", "templateVersion": 0},
            {"packageVersion": 1, "baselineScenarioID": "not-a-uuid"},
            {"packageVersion": 1, "baselineScenarioID": None},
        ]:
            self.assertFalse(validator.is_valid(invalid), invalid)
