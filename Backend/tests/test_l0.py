"""L0 steady-state adapter tests: energy balance closure, honest unknowns, determinism.

All inputs come from the artificial contract fixture — these tests verify the
computation wiring, NOT physical correctness against measurements.
"""
import unittest

from simunow_worker.models.codec import ScenarioSnapshotBuilder
from simunow_worker.models.domain import ProjectDocument
from simunow_worker.models.registry import native
from simunow_worker.adapters.l0 import steady_state

import fixture_factory


def snapshot(change=None):
    raw = fixture_factory.project()
    if change:
        change(raw)
    project = ProjectDocument.model_validate(native(raw))
    scenario_id = project.scenarios[0].id
    return ScenarioSnapshotBuilder.capture(project, scenario_id)


def metrics_by_name(result):
    return {m["name"]: m for m in result["metrics"]}


class SteadyStateTests(unittest.TestCase):

    def test_energy_balance_closes(self):
        result = steady_state.run(snapshot())
        balance = next(c for c in result["quality"]["checks"] if c["name"] == "energy_balance")
        self.assertEqual(balance["state"], "passed")
        self.assertLess(balance["max_residual_W"], 1e-6)

    def test_representative_day_metrics_present(self):
        result = steady_state.run(snapshot())
        metrics = metrics_by_name(result)
        for name in ("coolingLoadPeak", "dailyCoolingEnergy", "averageRoomTemperature",
                     "estimatedElectricEnergy"):
            self.assertIn(name, metrics)
            self.assertIsNotNone(metrics[name]["value"], name)
        # Fixture: 32 degC outdoors, 25 degC setpoint, 3 kW unit — load must be positive.
        self.assertGreater(metrics["coolingLoadPeak"]["value"], 0)
        self.assertGreater(metrics["dailyCoolingEnergy"]["value"], 0)
        for metric in result["metrics"]:
            self.assertEqual(metric["fidelity"], "l0")
            self.assertEqual(metric["aggregation"], "representative_day")
            self.assertEqual(metric["method"], "l0_steady_state")

    def test_internal_gains_increase_cooling_load(self):
        def no_gains(raw):
            raw["scenarios"][0]["inputs"]["usage"]["occupants"] = []
            raw["scenarios"][0]["inputs"]["usage"]["equipment"] = []
        with_gains = steady_state.run(snapshot())
        without = steady_state.run(snapshot(no_gains))
        self.assertGreater(metrics_by_name(with_gains)["dailyCoolingEnergy"]["value"],
                           metrics_by_name(without)["dailyCoolingEnergy"]["value"])

    def test_unknown_setpoint_yields_missing_not_zero(self):
        def break_setpoint(raw):
            raw["scenarios"][0]["inputs"]["controls"][0]["setpoint"] = \
                fixture_factory.unknown("No thermostat reading available")
        result = steady_state.run(snapshot(break_setpoint))
        metrics = metrics_by_name(result)
        for name in ("averageRoomTemperature", "coolingLoadPeak",
                     "dailyCoolingEnergy", "estimatedElectricEnergy"):
            self.assertIsNone(metrics[name]["value"], name)
            self.assertIn("missing_reason", metrics[name])

    def test_unknown_cop_blocks_electric_estimate_only(self):
        def break_cop(raw):
            raw["scenarios"][0]["inputs"]["hvac"][0]["definition"]["payload"]["cop"] = \
                fixture_factory.unknown("Manufacturer sheet not supplied")
        result = steady_state.run(snapshot(break_cop))
        metrics = metrics_by_name(result)
        self.assertIsNone(metrics["estimatedElectricEnergy"]["value"])
        self.assertIsNotNone(metrics["dailyCoolingEnergy"]["value"])

    def test_undersized_unit_raises_average_temperature(self):
        def tiny_unit(raw):
            raw["scenarios"][0]["inputs"]["hvac"][0]["definition"]["payload"]["coolingCapacity"] = \
                fixture_factory.known(200, "W")
        result = steady_state.run(snapshot(tiny_unit))
        metrics = metrics_by_name(result)
        self.assertEqual(metrics["capacityAdequate"]["value"], False)
        self.assertGreater(metrics["averageRoomTemperature"]["value"], 25.0)

    def test_no_tariff_means_no_cost(self):
        result = steady_state.run(snapshot())
        metrics = metrics_by_name(result)
        self.assertIsNone(metrics["dailyCost"]["value"])
        self.assertIn("不编造费用", metrics["dailyCost"]["missing_reason"])

    def test_tariff_cost_uses_same_day(self):
        def add_tariff(raw):
            raw["scenarios"][0]["evaluation"]["cost"] = {
                "currency": "HKD",
                "tariffs": [{"startMinute": 0, "endMinute": 1440,
                             "rate": fixture_factory.known(1.5, "currency/kWh")}],
                "quotes": []}
        result = steady_state.run(snapshot(add_tariff))
        metrics = metrics_by_name(result)
        electric = metrics["estimatedElectricEnergy"]["value"]
        # Cost is computed from the unrounded electric energy, then rounded to 4 decimals.
        self.assertAlmostEqual(metrics["dailyCost"]["value"], electric * 1.5, places=2)
        self.assertEqual(metrics["dailyCost"]["unit"], "HKD")

    def test_deterministic(self):
        first = steady_state.run(snapshot())
        second = steady_state.run(snapshot())
        self.assertEqual(first, second)

    def test_assumptions_declared(self):
        result = steady_state.run(snapshot())
        self.assertTrue(any("L0" in a for a in result["assumptions"]))
        self.assertTrue(any("COP" in a for a in result["assumptions"]))


if __name__ == "__main__":
    unittest.main()
