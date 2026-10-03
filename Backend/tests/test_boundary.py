import json
import unittest
from copy import deepcopy
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
        # ADR-012: per-person sensible heat is 57 W (measured EnergyPlus split
        # of the 70 W activity level); the L2 field sees the same sensible
        # watts as the L1 People object. Latent (13 W) is L1-only.
        self.assertEqual(mapped["occupantSensibleW"], 8 * 57)
        self.assertEqual(sum(item["watts"] for item in mapped["heatSources"] if item["name"] == "occupants"), 456)
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

    def test_second_window_averages_into_the_boundary_flux(self):
        # ADR-017: the DTO flux is the area-weighted mean over ALL windows,
        # not the first window's literal. Single-window rooms stay at 80.
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
                "heatFluxWm2": {"value": 40.0, "unit": "W/m2", "source": "user"},
            }
        )
        mapped = map_l2_boundary(draft, None)
        total_w = 80.0 * 1.5 * 1.3 + 40.0 * 1.0 * 1.0
        total_area = 1.5 * 1.3 + 1.0 * 1.0
        self.assertAlmostEqual(mapped["windowHeatFluxWm2"], total_w / total_area)
        self.assertNotEqual(mapped["windowHeatFluxWm2"], 80.0)

    def test_l1_window_heat_replaces_draft_flux(self):
        l1 = {
            "metrics": [
                {"name": "window_heat_w", "value": 390.0, "omitted": False},
                {"name": "opaque_heat_w", "value": 200.0, "omitted": False},
            ]
        }
        mapped = map_l2_boundary(OFFICE, l1)
        self.assertAlmostEqual(mapped["windowHeatFluxWm2"], 200.0)
        self.assertEqual(mapped["opaqueHeatW"], 200.0)
        self.assertEqual(mapped["omitted"], [])

    def test_omitted_l1_window_does_not_invent_flux(self):
        l1 = {"metrics": [{"name": "window_heat_w", "value": None, "omitted": True}]}
        mapped = map_l2_boundary(OFFICE, l1)
        self.assertEqual(mapped["windowHeatFluxWm2"], 80)
        self.assertIsNone(mapped["opaqueHeatW"])
        self.assertIn("envelope_u_value", mapped["omitted"])


if __name__ == "__main__":
    unittest.main()
