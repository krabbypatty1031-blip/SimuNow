"""Occupied hours must reach the IDF. AlwaysOn is only for rooms that have no schedule."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

from simunow_worker.models.l1_room import project_to_l1_room

ROOT = Path(__file__).resolve().parents[2]
P1 = ROOT / "test" / "p1"
sys.path.insert(0, str(P1))

OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]


class OccupiedScheduleTests(unittest.TestCase):
    def test_office_idf_uses_occupied_window_not_always_on_people(self):
        import write_idf as wi

        room = project_to_l1_room(OFFICE)
        with tempfile.TemporaryDirectory() as tmp:
            text = wi.write_idf(room, Path(tmp) / "room.idf").read_text(encoding="utf-8")
        self.assertIn("Schedule:Compact", text)
        self.assertIn("Until: 08:00, 0.0", text)
        self.assertIn("Until: 18:00, 1.0", text)
        self.assertIn("Until: 24:00, 0.0", text)
        self.assertIn("People, Occupants, Room, OccupiedHours", text)
        self.assertIn("Lights, RoomLights, Room, OccupiedHours", text)
        self.assertIn("ElectricEquipment, PlugLoads, Room, OccupiedHours", text)
        self.assertIn("IdealAC, HVACHours, RoomSupply", text)
        # Infiltration is envelope leakage, not a people schedule.
        self.assertIn("ZoneInfiltration:DesignFlowRate, Infil, Room, AlwaysOn", text)
        self.assertNotIn("People, Occupants, Room, AlwaysOn", text)

    def test_shorter_occupied_window_rewrites_idf(self):
        import write_idf as wi

        draft = json.loads(json.dumps(OFFICE))
        draft["occupancy"]["schedule"]["end"] = "12:00"
        draft["hvac"]["schedule"]["end"] = "12:00"
        room = project_to_l1_room(draft)
        with tempfile.TemporaryDirectory() as tmp:
            text = wi.write_idf(room, Path(tmp) / "room.idf").read_text(encoding="utf-8")
        self.assertIn("Until: 12:00, 1.0", text)
        self.assertNotIn("Until: 18:00, 1.0", text)

    def test_p1_fixture_without_schedule_keeps_always_on(self):
        import room_input as ri
        import write_idf as wi

        room = ri.load_room(P1 / "fixtures" / "room_p1.json")
        self.assertNotIn("schedule", room)
        with tempfile.TemporaryDirectory() as tmp:
            text = wi.write_idf(room, Path(tmp) / "room.idf").read_text(encoding="utf-8")
        self.assertIn("People, Occupants, Room, AlwaysOn", text)
        self.assertIn("IdealAC, , RoomSupply", text)
        self.assertNotIn("Schedule:Compact", text)

    def test_people_object_uses_occupant_count_not_seat_count(self):
        import write_idf as wi

        room = project_to_l1_room(OFFICE)
        with tempfile.TemporaryDirectory() as tmp:
            text = wi.write_idf(room, Path(tmp) / "room.idf").read_text(encoding="utf-8")
        self.assertIn("People, Occupants, Room, OccupiedHours, People, 8,", text)
        self.assertNotIn("People, Occupants, Room, OccupiedHours, People, 4,", text)

    def test_people_activity_follows_template_sensible_plus_constant_latent(self):
        """ADR-012: occupantSensibleW is per-person SENSIBLE heat. The People
        activity level = sensible + latent (13, measured split, L1-only q_cool
        term), so both layers count the same sensible watts."""
        import write_idf as wi

        draft = json.loads(json.dumps(OFFICE))
        sensible = 30.0
        draft["occupancy"]["occupantSensibleW"]["value"] = sensible
        room = project_to_l1_room(draft)
        with tempfile.TemporaryDirectory() as tmp:
            text = wi.write_idf(room, Path(tmp) / "room.idf").read_text(encoding="utf-8")
        activity = sensible + wi.OCCUPANT_LATENT_W
        self.assertIn(f"Schedule:Constant, Activity, ActivityLevel, {activity:g}", text)

    def test_office_people_pair_keeps_p3_activity_bit_for_bit(self):
        """After ADR-012 alignment the office template (sensible 57 + latent 13)
        keeps the exact P3 People activity number 70, so the L1 hand-test values
        stay valid without a re-run. The engine derives the sensible split
        itself; the SHF literal stays for legibility."""
        import write_idf as wi

        room = project_to_l1_room(OFFICE)
        self.assertEqual(room["gains"]["people_w"]["value"], 57.0)
        with tempfile.TemporaryDirectory() as tmp:
            text = wi.write_idf(room, Path(tmp) / "room.idf").read_text(encoding="utf-8")
        self.assertIn("Schedule:Constant, Activity, ActivityLevel, 70", text)
        self.assertIn("People, Occupants, Room, OccupiedHours, People, 8, , , 0.3", text)


if __name__ == "__main__":
    unittest.main()
