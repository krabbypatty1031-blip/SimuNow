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
        # Supply stays the one full-wall band: the writer still places it on
        # the x=0 wall as a full-span height band, so velocity is scaled to
        # keep the project supply m3/s (P4-07A keeps this simplification).
        room = project_to_l2_room(OFFICE)
        size_y = 6.0
        supply_span = 3.25 - 2.75
        self.assertAlmostEqual(room["supply"]["u_m_s"]["value"], 1.2 * supply_span / size_y)
        self.assertIn(
            "supply band spans the full wall; velocity scaled to preserve project supply m3/s",
            room["assumptions"],
        )
        # Windows are per-rectangle since P4-07: the office window keeps its
        # own declared 80 W/m2 — no band scaling spreads it over the wall.
        self.assertEqual(len(room["windows"]), 1)
        self.assertEqual(room["windows"][0]["wall"], "xMax")
        self.assertAlmostEqual(room["windows"][0]["q_w_m2"]["value"], 80.0)
        self.assertAlmostEqual(room["windows"][0]["area_m2"]["value"], 1.5 * 1.3)
        self.assertIn(
            "each window enters at its own wall, span and height; total window W is the sum over windows",
            room["assumptions"],
        )

    def test_moving_window_along_its_wall_changes_hash(self):
        # P4-07 acceptance: the same watts at a different span position must
        # reach the mesh, so the hash must move with the rectangle.
        from room_input import input_hash

        baseline = project_to_l2_room(OFFICE)
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"][0]["s0"]["value"] = 0.5
        draft["geometry"]["openings"][0]["s1"]["value"] = 2.0
        moved = project_to_l2_room(draft)
        self.assertAlmostEqual(moved["windows"][0]["q_w_m2"]["value"], 80.0)
        self.assertAlmostEqual(moved["windows"][0]["area_m2"]["value"], baseline["windows"][0]["area_m2"]["value"])
        self.assertNotEqual(input_hash(baseline), input_hash(moved))

    def test_second_window_keeps_its_own_watts_and_position(self):
        # ADR-018 (L2 side, P4-07 revision): each declared-flux window injects
        # its own watts at its own rectangle; nothing collapses into a band.
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"].append(
            {
                "id": "W2",
                "kind": "window",
                "wall": "yMax",
                "s0": {"value": 1.0, "unit": "m", "source": "user"},
                "s1": {"value": 2.0, "unit": "m", "source": "user"},
                "z0": {"value": 1.0, "unit": "m", "source": "user"},
                "z1": {"value": 2.0, "unit": "m", "source": "user"},
                "heatFluxWm2": {"value": 80.0, "unit": "W/m2", "source": "user"},
            }
        )
        room = project_to_l2_room(draft)
        self.assertEqual(len(room["windows"]), 2)
        by_wall = {entry["wall"]: entry for entry in room["windows"]}
        # Both rectangles keep their declared geometry and flux.
        self.assertEqual(by_wall["xMax"]["s0_m"]["value"], 2.25)
        self.assertEqual(by_wall["yMax"]["s0_m"]["value"], 1.0)
        self.assertAlmostEqual(by_wall["xMax"]["q_w_m2"]["value"], 80.0)
        self.assertAlmostEqual(by_wall["yMax"]["q_w_m2"]["value"], 80.0)
        # Total watts over the emitted rectangles == the draft sum.
        total = sum(entry["q_w_m2"]["value"] * entry["area_m2"]["value"] for entry in room["windows"])
        self.assertAlmostEqual(total, 80.0 * 1.5 * 1.3 + 80.0 * 1.0 * 1.0)
        self.assertAlmostEqual(room["window_area_m2"]["value"], 1.5 * 1.3 + 1.0 * 1.0)

    def test_second_window_without_flux_declares_zero_watts(self):
        # A window with no declared flux brings area (L1 counts it) and a
        # declared 0 W to the field; no flux is invented for it.
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"].append(
            {
                "id": "W2",
                "kind": "window",
                "wall": "yMax",
                "s0": {"value": 1.0, "unit": "m", "source": "user"},
                "s1": {"value": 2.0, "unit": "m", "source": "user"},
                "z0": {"value": 1.0, "unit": "m", "source": "user"},
                "z1": {"value": 2.0, "unit": "m", "source": "user"},
            }
        )
        room = project_to_l2_room(draft)
        self.assertEqual(len(room["windows"]), 2)
        by_wall = {entry["wall"]: entry for entry in room["windows"]}
        self.assertAlmostEqual(by_wall["yMax"]["q_w_m2"]["value"], 0.0)
        self.assertAlmostEqual(by_wall["xMax"]["q_w_m2"]["value"], 80.0)
        self.assertAlmostEqual(room["window_area_m2"]["value"], 1.5 * 1.3 + 1.0 * 1.0)

    def test_same_wall_overlapping_windows_merge_conserving_watts(self):
        # The editor allows any placement; two windows claiming the same wall
        # area merge into one rectangle whose q x area == the summed watts.
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"].append(
            {
                "id": "W2",
                "kind": "window",
                "wall": "xMax",
                "s0": {"value": 3.0, "unit": "m", "source": "user"},
                "s1": {"value": 4.5, "unit": "m", "source": "user"},
                "z0": {"value": 1.2, "unit": "m", "source": "user"},
                "z1": {"value": 2.0, "unit": "m", "source": "user"},
                "heatFluxWm2": {"value": 40.0, "unit": "W/m2", "source": "user"},
            }
        )
        room = project_to_l2_room(draft)
        self.assertEqual(len(room["windows"]), 1)
        merged = room["windows"][0]
        # Bounding box of 2.25..3.75 x 0.9..2.2 and 3.0..4.5 x 1.2..2.0.
        self.assertEqual(merged["s0_m"]["value"], 2.25)
        self.assertEqual(merged["s1_m"]["value"], 4.5)
        self.assertEqual(merged["z0_m"]["value"], 0.9)
        self.assertEqual(merged["z1_m"]["value"], 2.2)
        watts = merged["q_w_m2"]["value"] * merged["area_m2"]["value"]
        self.assertAlmostEqual(watts, 80.0 * 1.5 * 1.3 + 40.0 * 1.5 * 0.8)
        self.assertIn(
            "same-wall overlapping windows are merged into one rectangle; total window W is conserved",
            room["assumptions"],
        )

    def test_disjoint_same_wall_windows_do_not_merge(self):
        # Stacked windows on one wall that do not share area stay separate
        # patches; the three-direction cuts separate them in the mesh.
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"].append(
            {
                "id": "W2",
                "kind": "window",
                "wall": "xMax",
                "s0": {"value": 2.25, "unit": "m", "source": "user"},
                "s1": {"value": 3.75, "unit": "m", "source": "user"},
                "z0": {"value": 2.3, "unit": "m", "source": "user"},
                "z1": {"value": 2.7, "unit": "m", "source": "user"},
                "heatFluxWm2": {"value": 60.0, "unit": "W/m2", "source": "user"},
            }
        )
        room = project_to_l2_room(draft)
        self.assertEqual(len(room["windows"]), 2)
        self.assertAlmostEqual(sum(entry["q_w_m2"]["value"] * entry["area_m2"]["value"] for entry in room["windows"]),
                               80.0 * 1.5 * 1.3 + 60.0 * 1.5 * 0.4)

    def test_window_overlapping_supply_or_return_band_on_xmin_is_rejected(self):
        # The inlet/outlet bands own the full xMin span at their heights; a
        # window there would lose its watts to those faces. Honest failure
        # with the reason, never a silent watt loss.
        # Office return band z 1.85..2.05: the moved window 0.9..2.2 hits it.
        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"][0]["wall"] = "xMin"
        with self.assertRaises(ValueError) as caught:
            project_to_l2_room(draft)
        self.assertIn("return", str(caught.exception))
        # Office supply band z 2.48..2.66: a window above it hits that instead.
        draft["geometry"]["openings"][0]["z0"]["value"] = 2.3
        draft["geometry"]["openings"][0]["z1"]["value"] = 2.7
        with self.assertRaises(ValueError) as caught:
            project_to_l2_room(draft)
        self.assertIn("supply", str(caught.exception))
        # Between the bands (z 2.05..2.48) the xMin window is a legal patch.
        draft["geometry"]["openings"][0]["z0"]["value"] = 2.1
        draft["geometry"]["openings"][0]["z1"]["value"] = 2.4
        room = project_to_l2_room(draft)
        self.assertEqual(room["windows"][0]["wall"], "xMin")

    def test_window_off_the_room_or_off_its_wall_is_rejected(self):
        from copy import deepcopy as _dc

        draft = deepcopy(OFFICE)
        draft["geometry"]["openings"][0]["s1"]["value"] = 7.0
        with self.assertRaises(ValueError):
            project_to_l2_room(draft)
        draft = _dc(OFFICE)
        draft["geometry"]["openings"][0]["z1"]["value"] = 3.5
        with self.assertRaises(ValueError):
            project_to_l2_room(draft)
        draft = _dc(OFFICE)
        draft["geometry"]["openings"][0]["wall"] = "ceiling"
        with self.assertRaises(ValueError):
            project_to_l2_room(draft)

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
            self.assertIn("window0", mesh)
            self.assertIn("walls", mesh)
            self.assertNotIn("frontAndBack", mesh)
            self.assertTrue((dest / "0" / "T").is_file())
            self.assertIn("inlet", u_text)
            self.assertNotIn("buoyantBoussinesqSimpleFoam", mesh)


class FurnitureMappingTests(unittest.TestCase):
    """2026-10-04: dragged furniture must survive the whole chain to L1/L2.

    The App writes obstacles as origin/size/kind boxes (the drag placement
    shape); the mapper must hand the case writer contract AABBs the loader
    accepts, so a drop in the editor becomes blocked cells in the L2 case.
    """

    @staticmethod
    def _furnished_draft() -> dict:
        draft = deepcopy(OFFICE)
        draft["geometry"]["obstacles"] = [
            {
                "id": "F1",
                "kind": "desk",
                "origin": {"x": 1.0, "y": 1.2, "z": 0.0},
                "size": {"x": 1.2, "y": 0.7, "z": 0.75},
            },
            {
                "id": "F2",
                "kind": "screen",
                "origin": {"x": 3.4, "y": 3.3, "z": 0.0},
                "size": {"x": 0.5, "y": 0.5, "z": 0.9},
            },
        ]
        return draft

    def test_obstacles_map_to_contract_aabbs_with_disclosure(self):
        room = project_to_l2_room(self._furnished_draft())
        self.assertEqual(len(room["obstacles"]), 2)
        first = room["obstacles"][0]
        self.assertEqual(first["id"], "F1")
        self.assertEqual(first["kind"], "desk")
        self.assertEqual(first["x0_m"]["value"], 1.0)
        self.assertEqual(first["y0_m"]["value"], 1.2)
        self.assertEqual(first["z0_m"]["value"], 0.0)
        self.assertEqual(first["x1_m"]["value"], 2.2)
        self.assertEqual(first["y1_m"]["value"], 1.9)
        self.assertEqual(first["z1_m"]["value"], 0.75)
        self.assertIn(
            "furniture boxes enter the L2 case as blocked cells (boxToCell/subsetMesh)",
            room["assumptions"],
        )
        self.assertIn(
            "furniture kind (desk/chair/cabinet/screen) is a display label; the solver sees one blocked box per piece",
            room["assumptions"],
        )
        self.assertNotIn("omitted: furniture_boxes", room["assumptions"])

    def test_furniture_moves_the_input_hash(self):
        from room_input import input_hash

        baseline = project_to_l2_room(OFFICE)
        furnished = project_to_l2_room(self._furnished_draft())
        self.assertNotEqual(input_hash(baseline), input_hash(furnished))
        # Same box, one metre over: moving a desk is a different room.
        moved = self._furnished_draft()
        moved["geometry"]["obstacles"][0]["origin"]["x"] = 2.0
        self.assertNotEqual(input_hash(furnished), input_hash(project_to_l2_room(moved)))

    def test_furnished_mapping_feeds_loader_and_case_writer(self):
        from room_input import load_room
        from write_openfoam_room import write_openfoam_room

        room = project_to_l2_room(self._furnished_draft())
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            # The mapped room must be loadable as-is: the disclosure the
            # loader demands is exactly the one the mapper emits.
            room_path = root / "room.json"
            room_path.write_text(json.dumps(room), encoding="utf-8")
            loaded = load_room(room_path)
            self.assertEqual(len(loaded["obstacles"]), 2)
            case = write_openfoam_room(loaded, root / "case")
            toposet = (case / "system" / "topoSetDict").read_text(encoding="utf-8")
            self.assertIn("boxToCell", toposet)
            self.assertIn("(1.000000 0.000000 1.200000)", toposet)
            self.assertIn("(3.900000 0.900000 3.800000)", toposet)

    def test_obstacle_leaving_the_room_is_rejected(self):
        draft = self._furnished_draft()
        draft["geometry"]["obstacles"][0]["size"]["x"] = 9.0
        with self.assertRaises(ValueError) as caught:
            project_to_l2_room(draft)
        self.assertIn("leaves the room box", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
