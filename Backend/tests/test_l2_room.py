"""L2 room mapping must not invent envelope UA or treat seats as people."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from copy import deepcopy
from pathlib import Path

from simunow_worker.models.l2_room import project_to_l2_room

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]
P1 = ROOT / "test" / "p1"
if str(P1) not in sys.path:
    sys.path.insert(0, str(P1))


class L2RoomMappingTests(unittest.TestCase):
    def test_office_uses_supply_temperature_not_setpoint(self):
        room = project_to_l2_room(OFFICE)
        self.assertEqual(room["coordinates"]["system"], "metre_right_handed_z_up")
        self.assertEqual(room["size"]["x_m"]["value"], 6)
        self.assertEqual(room["supply"]["t_c"]["value"], 16)
        self.assertEqual(room["setpoint_c"]["value"], 26)
        self.assertNotEqual(room["supply"]["t_c"]["value"], room["setpoint_c"]["value"])
        self.assertEqual(room["gains"]["n_people"]["value"], 8)
        self.assertEqual(len(room["seats"]), 8)
        self.assertEqual(room["gains"]["n_people"]["value"], len(room["seats"]))
        self.assertEqual(room["seat_height_m"]["value"], 1.1)

    def test_office_omits_furniture_envelope_and_quality_pass(self):
        room = project_to_l2_room(OFFICE)
        self.assertIn("omitted: furniture_boxes", room["assumptions"])
        self.assertIn("omitted: envelope_u_value", room["assumptions"])
        self.assertNotIn("quality", room)
        self.assertNotIn("ua_opaque_w_k", room.get("l1", {}))
        self.assertEqual(room["ventilation"]["outdoor_m3_s"]["value"], 0.02)
        self.assertAlmostEqual(room["ventilation"]["recirculated_m3_s"]["value"], 0.088)

    def test_changing_occupant_count_changes_people_not_seats(self):
        draft = deepcopy(OFFICE)
        draft["occupancy"]["occupantCount"]["value"] = 3
        room = project_to_l2_room(draft)
        self.assertEqual(room["gains"]["n_people"]["value"], 3)
        self.assertEqual(len(room["seats"]), 8)
        # ADR-012: people_w is per-person SENSIBLE heat (57 W office template).
        self.assertEqual(room["gains"]["people_w"]["value"], 57)

    def test_changing_supply_speed_changes_hash(self):
        from room_input import input_hash

        baseline = project_to_l2_room(OFFICE)
        draft = deepcopy(OFFICE)
        draft["hvac"]["supplySpeedMs"]["value"] = 0.8
        changed = project_to_l2_room(draft)
        # Full-wall band: velocity scales by patch_span/wall_span to keep the
        # project supply m3/s, so the case value is not the project value.
        size_y = 6.0
        supply_span = 3.25 - 2.75
        self.assertAlmostEqual(changed["supply"]["u_m_s"]["value"], 0.8 * supply_span / size_y)
        self.assertGreater(baseline["supply"]["u_m_s"]["value"], changed["supply"]["u_m_s"]["value"])
        self.assertNotEqual(input_hash(baseline), input_hash(changed))

    def test_band_scaling_preserves_project_supply_flow_and_window_watts(self):
        # The P1 case writer can only make full-wall bands. Totals stay physical
        # by scaling velocity/flux; the geometry simplification is recorded.
        room = project_to_l2_room(OFFICE)
        size_y = 6.0
        supply_span = 3.25 - 2.75
        window_span = 3.75 - 2.25
        self.assertAlmostEqual(room["supply"]["u_m_s"]["value"], 1.2 * supply_span / size_y)
        self.assertAlmostEqual(room["window"]["q_w_m2"]["value"], 80.0 * window_span / size_y)
        self.assertIn(
            "supply band spans the full wall; velocity scaled to preserve project supply m3/s",
            room["assumptions"],
        )
        self.assertIn(
            "window band spans the full wall; flux scaled to preserve total window W",
            room["assumptions"],
        )

    def test_incomplete_draft_is_rejected(self):
        with self.assertRaises(ValueError):
            project_to_l2_room({"schemaVersion": 2, "name": "空"})

    def test_mapped_office_writes_case_without_solver(self):
        from write_openfoam_room import write_openfoam_room

        room = project_to_l2_room(OFFICE)
        with tempfile.TemporaryDirectory() as tmp:
            dest = Path(tmp) / "case"
            write_openfoam_room(room, dest)
            u_text = (dest / "0" / "U").read_text(encoding="utf-8")
            mesh = (dest / "system" / "blockMeshDict").read_text(encoding="utf-8")
            self.assertIn("inlet", mesh)
            self.assertIn("outlet", mesh)
            self.assertIn("window", mesh)
            self.assertTrue((dest / "0" / "T").is_file())
            self.assertIn("inlet", u_text)
            self.assertNotIn("buoyantBoussinesqSimpleFoam", mesh)


if __name__ == "__main__":
    unittest.main()
