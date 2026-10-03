"""Quality axes: run state, quality state, and seat values stay independent.

A failed quality gate must not fabricate seat temperatures, and a missing
quality log must not be reported as passed.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path
from uuid import uuid4

from simunow_worker.models.l2_accounting import evaluate_l2, quality_pass

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]

PASSED_GATES = {
    "checkMesh": "ok",
    "solverEnded": True,
    "monitorsStable": True,
    "massRelativeError": 0.0004,
    "massGate": 0.01,
    "energyRelativeError": 0.003,
    "energyGate": 0.05,
}

FAILED_MONITORS = dict(PASSED_GATES, monitorsStable=False)

SEATS = [
    {"id": "S1", "x": 1.5, "y": 1.5, "z": 1.1, "tC": 25.1, "uMag": 0.12},
    {"id": "S2", "x": 1.5, "y": 4.5, "z": 1.1, "tC": 25.4, "uMag": 0.09},
    {"id": "S3", "x": 4.5, "y": 1.5, "z": 1.1, "tC": 24.8, "uMag": 0.03, "lowSpeedAbsoluteError": True},
    {"id": "S4", "x": 4.5, "y": 4.5, "z": 1.1, "tC": 25.0, "uMag": 0.05},
]


def _identity() -> dict:
    return {
        "runID": str(uuid4()),
        "scenarioID": str(uuid4()),
        "inputHash": "l2-quality-test",
    }


def _metric(result: dict, name: str) -> dict:
    return next(item for item in result["metrics"] if item["name"] == name)


class QualityGateTests(unittest.TestCase):
    def test_every_gate_is_required_for_pass(self):
        self.assertTrue(quality_pass(PASSED_GATES))
        self.assertFalse(quality_pass(FAILED_MONITORS))
        self.assertFalse(quality_pass(dict(PASSED_GATES, checkMesh="failed")))
        self.assertFalse(quality_pass(dict(PASSED_GATES, solverEnded=False)))

    def test_missing_or_partial_logs_never_pass(self):
        self.assertFalse(quality_pass(None))
        self.assertFalse(quality_pass({}))
        partial = dict(PASSED_GATES)
        del partial["energyRelativeError"]
        self.assertFalse(quality_pass(partial))

    def test_relative_error_must_be_under_gate(self):
        self.assertFalse(quality_pass(dict(PASSED_GATES, massRelativeError=0.02)))
        self.assertFalse(quality_pass(dict(PASSED_GATES, energyRelativeError=0.06)))


class QualityAxesTests(unittest.TestCase):
    def test_failed_quality_keeps_run_succeeded_and_omits_seats(self):
        result = evaluate_l2(
            _identity(),
            OFFICE,
            {"qualityDetail": FAILED_MONITORS, "seatSamples": SEATS, "pipelineCompleted": True},
        )
        self.assertEqual(result["state"], "succeeded")
        self.assertEqual(result["quality"], "failed")
        self.assertEqual(result["qualityDetail"]["monitorsStable"], False)
        self.assertIsNone(result["seatSamples"])
        for name in ("seat_t_c_min", "seat_t_c_max", "seat_u_mag_max"):
            metric = _metric(result, name)
            self.assertTrue(metric["omitted"])
            self.assertIsNone(metric["value"])
            self.assertEqual(metric["fidelity"], "l2")

    def test_passed_quality_reports_seat_values_and_detail(self):
        result = evaluate_l2(
            _identity(),
            OFFICE,
            {"qualityDetail": PASSED_GATES, "seatSamples": SEATS, "pipelineCompleted": True},
        )
        self.assertEqual(result["state"], "succeeded")
        self.assertEqual(result["quality"], "passed")
        self.assertEqual(result["qualityDetail"]["checkMesh"], "ok")
        self.assertEqual(len(result["seatSamples"]), 4)
        self.assertEqual(_metric(result, "seat_t_c_min")["value"], 24.8)
        self.assertEqual(_metric(result, "seat_t_c_max")["value"], 25.4)
        self.assertEqual(_metric(result, "seat_u_mag_max")["value"], 0.12)
        low = [seat for seat in result["seatSamples"] if seat.get("lowSpeedAbsoluteError")]
        self.assertEqual([seat["id"] for seat in low], ["S3"])

    def test_missing_quality_is_not_evaluated(self):
        result = evaluate_l2(
            _identity(),
            OFFICE,
            {"qualityDetail": None, "seatSamples": None, "pipelineCompleted": True},
        )
        self.assertEqual(result["state"], "succeeded")
        self.assertEqual(result["quality"], "notEvaluated")
        self.assertIsNone(result["qualityDetail"])
        self.assertTrue(_metric(result, "seat_t_c_min")["omitted"])

    def test_pipeline_failure_fails_state_and_keeps_quality_not_evaluated(self):
        result = evaluate_l2(
            _identity(),
            OFFICE,
            {"qualityDetail": None, "seatSamples": None, "pipelineCompleted": False},
        )
        self.assertEqual(result["state"], "failed")
        self.assertEqual(result["quality"], "notEvaluated")
        self.assertEqual(result["supplyTemperatureC"], 16)
        self.assertEqual(result["setpointC"], 26)
        self.assertTrue(_metric(result, "seat_t_c_min")["omitted"])

    def test_p1_quality_json_maps_to_contract_detail(self):
        from simunow_worker.models.l2_accounting import quality_detail

        p1_quality = {
            "pass": False,
            "input_hash": "abc",
            "checkMesh": "ok",
            "solver_end": True,
            "monitors": {"stable": False, "n_last": 20},
            "mass": {"relative_error": 0.001, "gate": 0.01, "pass": True},
            "energy": {"relative_error": 0.004, "gate": 0.05, "pass": True},
        }
        detail = quality_detail(p1_quality)
        self.assertEqual(detail["checkMesh"], "ok")
        self.assertEqual(detail["solverEnded"], True)
        self.assertEqual(detail["monitorsStable"], False)
        self.assertEqual(detail["massRelativeError"], 0.001)
        self.assertEqual(detail["massGate"], 0.01)
        self.assertEqual(detail["energyRelativeError"], 0.004)
        self.assertEqual(detail["energyGate"], 0.05)
        self.assertEqual(quality_pass(detail), False)


if __name__ == "__main__":
    unittest.main()
