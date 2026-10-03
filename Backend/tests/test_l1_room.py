import json
import unittest
from copy import deepcopy
from pathlib import Path

from simunow_worker.models.l1_room import project_to_l1_room

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]


def _second_window() -> dict:
    """A user-added 1.0 x 1.0 m window on another wall, flux like the template's."""
    return {
        "id": "W2",
        "kind": "window",
        "wall": "yMax",
        "s0": {"value": 1.0, "unit": "m", "source": "user"},
        "s1": {"value": 2.0, "unit": "m", "source": "user"},
        "z0": {"value": 1.0, "unit": "m", "source": "user"},
        "z1": {"value": 2.0, "unit": "m", "source": "user"},
        "heatFluxWm2": {"value": 80.0, "unit": "W/m2", "source": "user"},
    }


class L1RoomMappingTests(unittest.TestCase):
    def test_office_maps_supply_not_setpoint_and_does_not_invent_ua(self):
        room = project_to_l1_room(OFFICE)
        self.assertEqual(room["coordinates"]["system"], "metre_right_handed_z_up")
        self.assertEqual(room["size"]["x_m"]["value"], 6)
        self.assertEqual(room["supply"]["t_c"]["value"], 16)
        self.assertEqual(room["l1"]["t_in_c"]["value"], 26)
        self.assertNotEqual(room["supply"]["t_c"]["value"], room["l1"]["t_in_c"]["value"])
        self.assertAlmostEqual(room["l1"]["window_area_m2"]["value"], 1.5 * 1.3)
        self.assertLess(room["l1"]["window_area_m2"]["value"], 6 * 1.3)
        self.assertNotIn("ua_opaque_w_k", room["l1"])
        self.assertNotIn("shgc", room["l1"])
        self.assertIn("omitted: envelope_u_value", room["assumptions"])
        self.assertEqual(room["l1"]["cop"]["value"], 3)
        self.assertEqual(room["l1"]["infil_m3_s"]["value"], 0.02)
        self.assertEqual(room["gains"]["n_people"]["value"], 8)
        self.assertEqual(room["schedule"]["occupancy"]["start"], "08:00")
        self.assertEqual(room["schedule"]["occupancy"]["end"], "18:00")
        self.assertEqual(len(OFFICE["occupancy"]["seats"]), 8)
        self.assertEqual(room["gains"]["n_people"]["value"], len(OFFICE["occupancy"]["seats"]))

    def test_second_window_adds_area_to_l1(self):
        # ADR-017: every window must reach the engine. The IDF takes ONE
        # east-wall window of the SUMMED area, so adding a window raises the
        # L1 load and with it the electricity cost.
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"].append(_second_window())
        room = project_to_l1_room(draft)
        self.assertAlmostEqual(room["l1"]["window_area_m2"]["value"], 1.5 * 1.3 + 1.0 * 1.0)
        self.assertIn(
            "all windows merge into one east-wall window; window area is the sum over windows",
            room["assumptions"],
        )

    def test_incomplete_draft_is_rejected(self):
        with self.assertRaises(ValueError):
            project_to_l1_room({"schemaVersion": 2, "name": "空"})


if __name__ == "__main__":
    unittest.main()
