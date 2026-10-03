"""Velocity glyphs and streamlines: nearest-cell U, quality-gated, no invented 0."""

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

from field_flow import build_flow, glyph_grid, integrate_streamline, write_flow  # noqa: E402
from room_input import RoomError  # noqa: E402


def _room() -> dict:
    return {
        "size": {"x_m": {"value": 6}, "y_m": {"value": 6}, "z_m": {"value": 2.8}},
        "seats": [{"id": "S1", "x_m": 3.0, "y_m": 3.0, "z_m": 1.1}],
        "supply": {
            "x_m": {"value": 0.0},
            "z0_m": {"value": 2.48},
            "z1_m": {"value": 2.66},
        },
        "return": {
            "x_m": {"value": 0.0},
            "z0_m": {"value": 0.2},
            "z1_m": {"value": 0.4},
        },
    }


# Uniform +X in the foam frame. contract_xyz maps it to the same +X.
CELLS = {
    "cx": [1.0, 5.0],
    "cy": [1.1, 2.57],
    "cz": [1.0, 5.0],
    "velocity": [(0.2, 0.0, 0.0), (0.2, 0.0, 0.0)],
}


class GlyphGridTests(unittest.TestCase):
    def test_glyphs_are_nearest_cell_contract_velocity(self):
        glyphs = glyph_grid(_room(), z_m=1.1, spacing_hint_m=2.0, **CELLS)
        self.assertGreaterEqual(len(glyphs), 4)
        for glyph in glyphs:
            self.assertAlmostEqual(glyph["ux"], 0.2)
            self.assertAlmostEqual(glyph["uy"], 0.0)
            self.assertAlmostEqual(glyph["uz"], 0.0)
            self.assertAlmostEqual(glyph["mag"], 0.2)
            self.assertEqual(glyph["z"], 1.1)

    def test_still_air_is_omitted_not_stored_as_zero(self):
        still = {
            "cx": [3.0],
            "cy": [1.1],
            "cz": [3.0],
            "velocity": [(0.0, 0.0, 0.0)],
        }
        glyphs = glyph_grid(_room(), z_m=1.1, spacing_hint_m=2.0, **still)
        self.assertEqual(glyphs, [])

    def test_flow_height_outside_the_room_is_rejected(self):
        with self.assertRaises(RoomError):
            glyph_grid(_room(), z_m=2.8, spacing_hint_m=2.0, **CELLS)


class StreamlineTests(unittest.TestCase):
    def test_uniform_plus_x_advances_along_x_and_stops_at_the_wall(self):
        points = integrate_streamline(
            _room(),
            (0.2, 3.0, 1.1),
            velocity=CELLS["velocity"],
            cx=CELLS["cx"],
            cy=CELLS["cy"],
            cz=CELLS["cz"],
        )
        self.assertGreaterEqual(len(points), 2)
        xs = [point["x"] for point in points]
        self.assertGreater(xs[-1], xs[0])
        self.assertLess(xs[-1], 6.0)
        self.assertTrue(all(abs(point["y"] - 3.0) < 1e-6 for point in points))


class WriteFlowTests(unittest.TestCase):
    def test_failed_quality_writes_no_flow_file(self):
        with tempfile.TemporaryDirectory() as folder:
            run_dir = Path(folder)
            result = write_flow(
                run_dir,
                _room(),
                z_m=1.1,
                input_hash="hash-1",
                quality_pass=False,
                **CELLS,
            )
            self.assertIsNone(result)
            self.assertFalse((run_dir / "field-flow.json").exists())

    def test_quality_passed_writes_contract_overlay(self):
        with tempfile.TemporaryDirectory() as folder:
            run_dir = Path(folder)
            result = write_flow(
                run_dir,
                _room(),
                z_m=1.1,
                input_hash="hash-1",
                quality_pass=True,
                **CELLS,
            )
            self.assertIsNotNone(result)
            payload = json.loads((run_dir / "field-flow.json").read_text(encoding="utf-8"))
            self.assertEqual(payload["schemaVersion"], 1)
            self.assertEqual(payload["kind"], "velocity_overlay")
            self.assertEqual(payload["quantity"], "air_velocity")
            self.assertEqual(payload["unit"], "m/s")
            self.assertEqual(payload["coordinateSystem"], "rightHandedZUp")
            self.assertEqual(payload["sampleMethod"], "nearest_cell")
            self.assertEqual(payload["streamlineMethod"], "rk2_nearest_cell")
            self.assertEqual(payload["inputHash"], "hash-1")
            self.assertEqual(payload["quality"], "passed")
            self.assertGreater(payload["stats"]["glyphCount"], 0)
            self.assertGreater(payload["stats"]["lineCount"], 0)
            self.assertAlmostEqual(payload["stats"]["maxMag"], 0.2)
            built = build_flow(_room(), z_m=1.1, **CELLS)
            self.assertEqual(len(payload["glyphs"]), built["stats"]["glyphCount"])


if __name__ == "__main__":
    unittest.main()
