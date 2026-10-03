"""Seat-height temperature slice: nearest-cell grid, masked, quality-gated.

Slice values come from the solve-mesh cell fields - the same source of truth
as seat samples - so display density can never change the physics. Cells
outside the fluid are masked invalid and never join statistics. No slice
file exists for a failed field.
"""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
P1 = ROOT / "test" / "p1"
if str(P1) not in sys.path:
    sys.path.insert(0, str(P1))

from field_slice import slice_grid, write_slice  # noqa: E402
from room_input import RoomError  # noqa: E402


def _room() -> dict:
    return {
        "size": {"x_m": {"value": 6}, "y_m": {"value": 6}, "z_m": {"value": 2.8}},
        "seats": [{"id": "S1", "x_m": 3.0, "y_m": 3.0, "z_m": 1.1}],
    }


# Two solve-mesh cells in foam Y-up; the contract grid at z=1.1 hits both.
CELLS = {
    "cx": [1.0, 5.0],
    "cy": [1.1, 1.1],
    "cz": [1.0, 5.0],
    "temperature": [298.15, 299.15],
}


class SliceGridTests(unittest.TestCase):
    def test_grid_is_nearest_cell_values_in_contract_axes(self):
        grid = slice_grid(
            _room(),
            z_m=1.1,
            spacing_hint_m=2.0,
            **CELLS,
        )
        # 6 m / 2.0 m hint -> 3 x 3 cell-centred grid.
        self.assertEqual(grid["shape"], {"nx": 3, "ny": 3})
        self.assertEqual(grid["axisOrder"], ["y", "x"])
        # values[j][i]: outer y, inner x. Cell centres land at 1.0 and 5.0.
        self.assertAlmostEqual(grid["values"][0][0], 25.0)  # near cold cell
        self.assertAlmostEqual(grid["values"][2][2], 26.0)  # near warm cell
        # Grid geometry is cell-centred: first centre, spacing, room frame.
        self.assertAlmostEqual(grid["originM"]["x"], 1.0)
        self.assertAlmostEqual(grid["originM"]["y"], 1.0)
        self.assertAlmostEqual(grid["spacingM"]["x"], 2.0)
        self.assertAlmostEqual(grid["spacingM"]["y"], 2.0)
        self.assertEqual(grid["zM"], 1.1)
        self.assertEqual(grid["unit"], "C")

    def test_mask_marks_fluid_points_and_stats_count_only_valid(self):
        # P1 rooms have no furniture, so an in-room height mask is all true;
        # the mask exists so wall/furniture interiors can never join stats.
        grid = slice_grid(_room(), z_m=1.1, spacing_hint_m=2.0, **CELLS)
        self.assertEqual(len(grid["valid"]), 3)
        self.assertTrue(all(all(row) for row in grid["valid"]))
        self.assertEqual(grid["stats"]["validCount"], 9)
        self.assertAlmostEqual(grid["stats"]["minC"], 25.0)
        self.assertAlmostEqual(grid["stats"]["maxC"], 26.0)

    def test_slice_height_outside_the_room_is_rejected(self):
        with self.assertRaises(RoomError):
            slice_grid(_room(), z_m=2.8, spacing_hint_m=2.0, **CELLS)
        with self.assertRaises(RoomError):
            slice_grid(_room(), z_m=0.0, spacing_hint_m=2.0, **CELLS)


class WriteSliceTests(unittest.TestCase):
    def test_failed_quality_writes_no_slice_file(self):
        with tempfile.TemporaryDirectory() as folder:
            run_dir = Path(folder)
            result = write_slice(
                run_dir,
                _room(),
                z_m=1.1,
                spacing_hint_m=2.0,
                input_hash="hash-1",
                quality_pass=False,
                **CELLS,
            )
            self.assertIsNone(result)
            self.assertFalse((run_dir / "field-slice.json").exists())

    def test_quality_passed_writes_contract_slice(self):
        with tempfile.TemporaryDirectory() as folder:
            run_dir = Path(folder)
            result = write_slice(
                run_dir,
                _room(),
                z_m=1.1,
                spacing_hint_m=2.0,
                input_hash="hash-1",
                quality_pass=True,
                **CELLS,
            )
            self.assertIsNotNone(result)
            payload = json.loads((run_dir / "field-slice.json").read_text(encoding="utf-8"))
            # Every axis/unit claim the plan demands is on the wire.
            self.assertEqual(payload["schemaVersion"], 1)
            self.assertEqual(payload["kind"], "temperature_slice")
            self.assertEqual(payload["quantity"], "air_temperature")
            self.assertEqual(payload["unit"], "C")
            self.assertEqual(payload["coordinateSystem"], "rightHandedZUp")
            self.assertEqual(payload["axisOrder"], ["y", "x"])
            self.assertEqual(payload["sampleMethod"], "nearest_cell")
            self.assertEqual(payload["inputHash"], "hash-1")
            self.assertEqual(payload["quality"], "passed")
            self.assertEqual(payload["shape"]["nx"], 3)
            self.assertEqual(len(payload["values"]), 3)
            self.assertEqual(len(payload["values"][0]), 3)
            self.assertEqual(len(payload["valid"]), 3)
            # stats count only valid cells.
            self.assertEqual(payload["stats"]["validCount"], 9)
            self.assertAlmostEqual(payload["stats"]["minC"], 25.0)
            self.assertAlmostEqual(payload["stats"]["maxC"], 26.0)


if __name__ == "__main__":
    unittest.main()
