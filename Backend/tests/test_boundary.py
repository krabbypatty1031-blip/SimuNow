import json
import unittest
from pathlib import Path

from simunow_worker.models.boundary import map_l2_boundary

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]


class BoundaryTests(unittest.TestCase):
    def test_supply_is_not_setpoint(self):
        mapped = map_l2_boundary(OFFICE, None)
        self.assertEqual(mapped["supplyTemperatureC"], 16)
        self.assertEqual(mapped["setpointC"], 26)
        self.assertEqual(mapped["windowHeatFluxWm2"], 80)
        self.assertEqual(mapped["lightingW"], 180)
        self.assertEqual(mapped["equipmentW"], 400)

    def test_occupant_sensible_counted_once(self):
        mapped = map_l2_boundary(OFFICE, None)
        self.assertEqual(mapped["occupantSensibleW"], 8 * 70)
        self.assertEqual(sum(item["watts"] for item in mapped["heatSources"] if item["name"] == "occupants"), 560)
        self.assertEqual(len([item for item in mapped["heatSources"] if item["name"] == "occupants"]), 1)
        self.assertIn("envelope_u_value", mapped["omitted"])

    def test_return_is_mapped_separately_from_supply_and_outdoor(self):
        mapped = map_l2_boundary(OFFICE, None)
        self.assertEqual(mapped["returnTerminal"]["id"], "RET1")
        self.assertEqual(mapped["returnTerminal"]["z0"], 1.85)
        self.assertEqual(mapped["supply"]["id"], "SUP1")
        self.assertEqual(mapped["supply"]["z0"], 2.48)
        self.assertNotEqual(mapped["returnTerminal"]["z0"], mapped["supply"]["z0"])
        self.assertEqual(mapped["outdoorAirM3s"], 0.02)
        self.assertAlmostEqual(mapped["recirculatedAirM3s"], 0.108 - 0.02)
        self.assertNotEqual(mapped["outdoorAirM3s"], mapped["recirculatedAirM3s"])


if __name__ == "__main__":
    unittest.main()
