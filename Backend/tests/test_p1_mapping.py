"""P2-05 mapping must match Swift scalars and must not invent L1 U-values or quality.pass."""

from __future__ import annotations

import json
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
OFFICE = REPO / "Fixtures" / "templates" / "office.json"


class P1MappingTests(unittest.TestCase):
    def test_office_window_area_is_patch_not_wall(self):
        from simunow_worker.models.p1_mapping import map_project_to_p1
        from simunow_worker.models.project import parse_project

        template = json.loads(OFFICE.read_text(encoding="utf-8"))
        draft = parse_project(template["project"])
        mapped = map_project_to_p1(draft)
        self.assertAlmostEqual(mapped["window_area_m2"], 1.5 * 1.3)
        self.assertNotAlmostEqual(mapped["window_area_m2"], 6 * 1.3)
        self.assertEqual(mapped["size_x_m"], 6)
        self.assertEqual(mapped["size_y_m"], 6)
        self.assertEqual(mapped["size_z_m"], 2.8)
        self.assertEqual(mapped["supply_t_c"], 16)
        self.assertEqual(mapped["supply"]["z0_m"], 2.48)
        self.assertEqual(mapped["return"]["z0_m"], 1.85)
        self.assertEqual(mapped["window"]["s0_m"], 2.25)
        self.assertEqual(mapped["window"]["s1_m"], 3.75)
        self.assertEqual(mapped["gains"]["lighting_w"], 180)
        self.assertEqual(mapped["seats"][0]["x_m"], 1.5)
        self.assertEqual(mapped["seat_ids"], ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8"])
        self.assertIn("l1.ua_opaque_w_k", mapped["omitted"])
        self.assertIn("weather_file", mapped["omitted"])
        self.assertNotIn("quality.pass", mapped)
        self.assertNotIn("quality", mapped)
