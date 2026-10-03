"""P2-01 project JSON must round-trip the same camelCase contract as Swift."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FIXTURES = REPO / "Fixtures"
SCHEMA = REPO / "Protocols" / "Schemas" / "project-draft.schema.json"

V1 = {
    "schemaVersion": 1,
    "id": "11111111-1111-1111-1111-111111111111",
    "name": "办公室",
    "spaceType": "office",
    "lengthUnit": "m",
    "coordinateSystem": "rightHandedZUp",
}


class ProjectModelTests(unittest.TestCase):
    def test_v1_is_not_a_complete_physical_model(self):
        from simunow_worker.models.project import has_complete_physical_model, parse_project

        draft = parse_project(V1)
        self.assertFalse(has_complete_physical_model(draft))
        self.assertIsNone(draft.get("geometry"))
        self.assertIsNone(draft.get("occupancy"))
        self.assertIsNone(draft.get("hvac"))
        # Migration must not invent a default rectangular room.
        self.assertNotIn("sizeX", draft)

    def test_v2_fixture_keeps_setpoint_separate_from_supply(self):
        from simunow_worker.models.project import has_complete_physical_model, parse_project

        payload = json.loads((FIXTURES / "project-v2-office.json").read_text(encoding="utf-8"))
        draft = parse_project(payload)
        self.assertTrue(has_complete_physical_model(draft))
        self.assertEqual(draft["hvac"]["setpointC"]["value"], 26)
        self.assertEqual(draft["hvac"]["supplyTemperatureC"]["value"], 16)
        self.assertNotEqual(
            draft["hvac"]["setpointC"]["value"],
            draft["hvac"]["supplyTemperatureC"]["value"],
        )
        self.assertEqual([seat["id"] for seat in draft["occupancy"]["seats"]], ["S1", "S2", "S3", "S4"])
        self.assertEqual(draft["lengthUnit"], "m")
        self.assertEqual(draft["coordinateSystem"], "rightHandedZUp")
        window = draft["geometry"]["openings"][0]
        self.assertEqual(window["s1"]["value"] - window["s0"]["value"], 1.5)
        self.assertLess(window["s1"]["value"] - window["s0"]["value"], draft["geometry"]["sizeY"]["value"])
        supply = draft["hvac"]["supply"]
        area = (supply["s1"]["value"] - supply["s0"]["value"]) * (supply["z1"]["value"] - supply["z0"]["value"])
        self.assertAlmostEqual(area, 0.09)
        from simunow_worker.models.project import supply_airflow_matches_speed

        self.assertTrue(supply_airflow_matches_speed(draft["hvac"]))
        self.assertEqual(draft["geometry"]["northYawDegrees"]["value"], 0)
        self.assertEqual(draft["geometry"]["northYawDegrees"]["unit"], "deg")

    def test_v2_fixture_pins_adr012_per_person_sensible_watts(self):
        # ADR-012: office/classroom templates carry 57 W per-person SENSIBLE
        # heat (measured EnergyPlus split 57 sensible + 13 latent). P2-05 keeps
        # the fixture on the template basis; a stale 70 W full-sensible figure
        # here would re-inflate L2 occupant heat to 8x70=560 W when the fixture
        # feeds boundary mapping, silently undoing the alignment.
        from simunow_worker.models.project import parse_project

        payload = json.loads((FIXTURES / "project-v2-office.json").read_text(encoding="utf-8"))
        draft = parse_project(payload)
        self.assertEqual(draft["occupancy"]["occupantSensibleW"]["value"], 57.0)

    def test_schema_requires_wall_span_and_optional_quantity_provenance(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        opening_required = schema["$defs"]["opening"]["required"]
        self.assertIn("s0", opening_required)
        self.assertIn("s1", opening_required)
        terminal_required = schema["$defs"]["terminal"]["required"]
        self.assertIn("s0", terminal_required)
        quantity_props = schema["$defs"]["quantity"]["properties"]
        self.assertIn("reference", quantity_props)
        self.assertIn("uncertainty", quantity_props)
        self.assertNotIn("reference", schema["$defs"]["quantity"]["required"])
        self.assertIn("supplyAirflowM3s", schema["$defs"]["hvac"]["required"])
        self.assertIn("northYawDegrees", schema["$defs"]["geometry"]["required"])

    def test_schema_documents_both_versions(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        versions = schema["properties"]["schemaVersion"]
        self.assertIn(1, versions.get("enum", []) or [versions.get("const")])
        self.assertIn(2, versions.get("enum", []))

    def test_schema_comfort_is_optional_and_names_four_keys(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        occupancy = schema["$defs"]["occupancy"]
        self.assertNotIn("comfort", occupancy["required"])
        self.assertIn("comfort", occupancy["properties"])
        comfort = schema["$defs"]["comfort"]
        for key in ("mrtC", "rhPct", "clo", "met"):
            self.assertIn(key, comfort["required"])
            self.assertIn(key, comfort["properties"])

    def test_schema_cost_assumptions_are_optional(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.assertNotIn("costAssumptions", schema["required"])
        self.assertIn("costAssumptions", schema["properties"])
        cost = schema["$defs"]["costAssumptions"]
        self.assertIn("currency", cost["required"])
        self.assertIn("source", cost["required"])
        self.assertNotIn("pricePerKWh", cost["required"])
        self.assertNotIn("payback_years", cost["properties"])
        self.assertNotIn("annual_kwh", cost["properties"])

    def test_v2_fixture_does_not_invent_a_tariff(self):
        from simunow_worker.models.project import parse_project

        payload = json.loads((FIXTURES / "project-v2-office.json").read_text(encoding="utf-8"))
        draft = parse_project(payload)
        self.assertNotIn("costAssumptions", draft)
        kept = parse_project({**payload, "costAssumptions": {"pricePerKWh": 1.2, "currency": "HKD", "source": "assumed"}})
        self.assertEqual(kept["costAssumptions"]["pricePerKWh"], 1.2)

    def test_v2_fixture_does_not_invent_comfort_zeros(self):
        from simunow_worker.models.project import parse_project

        payload = json.loads((FIXTURES / "project-v2-office.json").read_text(encoding="utf-8"))
        draft = parse_project(payload)
        self.assertNotIn("comfort", draft["occupancy"])

    def test_schema_weather_is_optional(self):
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        self.assertNotIn("weather", schema["required"])
        self.assertIn("weather", schema["properties"])
        day = schema["$defs"]["weatherDay"]
        self.assertIn("month", day["required"])
        self.assertIn("day", day["required"])
        self.assertIn("source", day["required"])

    def test_v2_fixture_resolves_missing_weather_to_july(self):
        from simunow_worker.models.project import parse_project
        from simunow_worker.models.weather import resolved_weather

        payload = json.loads((FIXTURES / "project-v2-office.json").read_text(encoding="utf-8"))
        draft = parse_project(payload)
        self.assertNotIn("weather", draft)
        self.assertEqual(resolved_weather(draft), (7, 15))


if __name__ == "__main__":
    unittest.main()
