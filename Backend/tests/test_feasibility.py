"""L2 seat coverage is a model gate, not a measured satisfaction rate.

Synthetic seats only: no OpenFOAM. A missing or failed field omits the
ratio. Out-of-domain seats leave the denominator instead of counting as
failures. Ratio 0 means every evaluated seat missed a gate.
"""

from __future__ import annotations

import unittest
from uuid import uuid4

from simunow_worker.models.feasibility import feasibility_metrics
from simunow_worker.models.l2_accounting import evaluate_l2

# Four in-band seats. S4 sits farthest from the 24.5 °C band center.
IN_BAND = [
    {"id": "S1", "tC": 24.5, "uMag": 0.05, "pmv": 0.0},
    {"id": "S2", "tC": 24.0, "uMag": 0.10, "pmv": 0.1},
    {"id": "S3", "tC": 25.2, "uMag": 0.15, "pmv": -0.2},
    {"id": "S4", "tC": 23.1, "uMag": 0.20, "pmv": 0.3},
]

OFFICE = {
    "hvac": {"supplyTemperatureC": {"value": 16}, "setpointC": {"value": 26}},
}

PASSED_QUALITY = {
    "checkMesh": "ok",
    "solverEnded": True,
    "monitorsStable": True,
    "massRelativeError": 0.001,
    "massGate": 0.01,
    "energyRelativeError": 0.004,
    "energyGate": 0.05,
}


def _by_name(metrics):
    return {metric["name"]: metric for metric in metrics}


class SeatGateTests(unittest.TestCase):
    def test_in_band_seats_with_pmv_cover_every_seat_and_name_the_farthest(self):
        metrics = feasibility_metrics(IN_BAND, quality_passed=True)
        by_name = _by_name(metrics)
        ratio = by_name["seat_pass_ratio"]
        self.assertFalse(ratio["omitted"])
        self.assertEqual(ratio["value"], 1.0)
        self.assertEqual(ratio["fidelity"], "l2")
        self.assertEqual(by_name["seat_pass_count"]["value"], 4)
        self.assertEqual(by_name["seat_eval_count"]["value"], 4)
        # Still name a worst seat: largest |tC - 24.5|, not "everyone passed".
        self.assertEqual(by_name["worst_seat_id"]["reason"], "S4")
        self.assertFalse(by_name["worst_seat_id"]["omitted"])

    def test_one_hot_seat_fails_the_temperature_gate(self):
        seats = [dict(row) for row in IN_BAND]
        seats[3] = {"id": "S4", "tC": 27.0, "uMag": 0.05, "pmv": 0.2}
        by_name = _by_name(feasibility_metrics(seats, quality_passed=True))
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 0.75)
        self.assertEqual(by_name["seat_pass_count"]["value"], 3)
        self.assertEqual(by_name["seat_eval_count"]["value"], 4)
        self.assertEqual(by_name["worst_seat_id"]["reason"], "S4")
        self.assertIn("温度门", by_name["worst_seat_reason"]["reason"])

    def test_omitted_seat_leaves_the_denominator(self):
        # 40 °C would win "farthest from 24.5" if a bug counted it.
        seats = [dict(row) for row in IN_BAND[:3]]
        seats.append({"id": "S9", "tC": 40.0, "uMag": 0.9, "omitted": True, "reason": "not_in_fluid"})
        by_name = _by_name(feasibility_metrics(seats, quality_passed=True))
        self.assertEqual(by_name["seat_eval_count"]["value"], 3)
        self.assertEqual(by_name["seat_pass_count"]["value"], 3)
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        self.assertNotEqual(by_name["worst_seat_id"]["reason"], "S9")
        self.assertIn("S9", by_name["seat_pass_ratio"]["reason"])
        self.assertIn("不计入分母", by_name["seat_pass_ratio"]["reason"])

    def test_out_of_iso_air_seat_is_not_a_failure(self):
        seats = [dict(row) for row in IN_BAND[:3]]
        seats.append({"id": "S9", "tC": 35.0, "uMag": 0.1, "pmv": 1.2})
        by_name = _by_name(feasibility_metrics(seats, quality_passed=True))
        self.assertEqual(by_name["seat_eval_count"]["value"], 3)
        self.assertEqual(by_name["seat_pass_count"]["value"], 3)
        self.assertIn("S9", by_name["seat_pass_ratio"]["reason"])

    def test_missing_pmv_does_not_fail_the_seat(self):
        seats = [
            {"id": "S1", "tC": 24.0, "uMag": 0.1},
            {"id": "S2", "tC": 25.0, "uMag": 0.1},
        ]
        by_name = _by_name(feasibility_metrics(seats, quality_passed=True))
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        self.assertEqual(by_name["seat_eval_count"]["value"], 2)

    def test_band_edges_pass_and_speed_breaks_a_temperature_tie(self):
        # |23-24.5| == |26-24.5|. The faster seat is worse. Both edges pass.
        seats = [
            {"id": "S1", "tC": 23.0, "uMag": 0.10, "pmv": 0.0},
            {"id": "S2", "tC": 26.0, "uMag": 0.25, "pmv": 0.0},
        ]
        by_name = _by_name(feasibility_metrics(seats, quality_passed=True))
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        self.assertEqual(by_name["worst_seat_id"]["reason"], "S2")

    def test_low_speed_flag_still_uses_the_speed_gate_and_stays_marked(self):
        seats = [
            {"id": "S1", "tC": 24.5, "uMag": 0.05, "pmv": 0.0, "lowSpeedAbsoluteError": True},
        ]
        by_name = _by_name(feasibility_metrics(seats, quality_passed=True))
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        self.assertIn("低速绝对误差", by_name["seat_pass_ratio"]["reason"])


class MissingFieldTests(unittest.TestCase):
    def test_failed_quality_omits_the_ratio_instead_of_zero(self):
        metrics = feasibility_metrics(IN_BAND, quality_passed=False)
        by_name = _by_name(metrics)
        ratio = by_name["seat_pass_ratio"]
        self.assertTrue(ratio["omitted"])
        self.assertIsNone(ratio["value"])
        self.assertNotEqual(ratio["value"], 0)
        self.assertTrue(ratio["reason"])
        for name in (
            "seat_pass_count",
            "seat_eval_count",
            "worst_seat_id",
            "worst_seat_reason",
            "infeasibleReason",
        ):
            self.assertTrue(by_name[name]["omitted"], name)
            self.assertIsNone(by_name[name]["value"], name)

    def test_no_seat_samples_omits_the_ratio(self):
        by_name = _by_name(feasibility_metrics(None, quality_passed=True))
        self.assertTrue(by_name["seat_pass_ratio"]["omitted"])
        self.assertIsNone(by_name["seat_pass_ratio"]["value"])

    def test_every_evaluated_seat_failing_is_zero_with_gates_and_no_recommendation(self):
        seats = [
            {"id": "S1", "tC": 28.0, "uMag": 0.10, "pmv": 0.0},
            {"id": "S2", "tC": 24.5, "uMag": 0.40, "pmv": 0.0},
            {"id": "S3", "tC": 24.5, "uMag": 0.10, "pmv": 0.9},
        ]
        metrics = feasibility_metrics(seats, quality_passed=True)
        by_name = _by_name(metrics)
        self.assertFalse(by_name["seat_pass_ratio"]["omitted"])
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 0.0)
        self.assertEqual(by_name["seat_pass_count"]["value"], 0)
        self.assertEqual(by_name["seat_eval_count"]["value"], 3)
        reason = by_name["infeasibleReason"]["reason"]
        self.assertFalse(by_name["infeasibleReason"]["omitted"])
        for gate in ("温度门", "风速门", "PMV门"):
            self.assertIn(gate, reason)
        blob = " ".join(str(metric.get("reason") or "") + metric["name"] for metric in metrics)
        self.assertNotIn("推荐方案", blob)
        self.assertNotIn("满意率", blob)


class EvaluateL2FeasibilityTests(unittest.TestCase):
    def _identity(self):
        return {"runID": str(uuid4()), "scenarioID": str(uuid4()), "inputHash": "feasibility-test"}

    def test_quality_passed_field_appends_coverage_without_changing_gates(self):
        context = {
            "pipelineCompleted": True,
            "qualityDetail": dict(PASSED_QUALITY),
            "seatSamples": [
                {"id": "S1", "x": 1, "y": 1, "z": 1.1, "tC": 24.5, "uMag": 0.05},
                {"id": "S2", "x": 2, "y": 2, "z": 1.1, "tC": 25.5, "uMag": 0.20},
            ],
        }
        result = evaluate_l2(self._identity(), OFFICE, context)
        self.assertEqual(result["quality"], "passed")
        by_name = _by_name(result["metrics"])
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        self.assertEqual(by_name["worst_seat_id"]["reason"], "S2")
        self.assertFalse(by_name["seat_t_c_min"]["omitted"])

    def test_failed_field_omits_coverage_and_does_not_invent_zero(self):
        context = {
            "pipelineCompleted": True,
            "qualityDetail": dict(PASSED_QUALITY, checkMesh="failed"),
            "seatSamples": [
                {"id": "S1", "x": 1, "y": 1, "z": 1.1, "tC": 24.5, "uMag": 0.05},
            ],
        }
        result = evaluate_l2(self._identity(), OFFICE, context)
        self.assertEqual(result["quality"], "failed")
        self.assertIsNone(result["seatSamples"])
        by_name = _by_name(result["metrics"])
        self.assertTrue(by_name["seat_pass_ratio"]["omitted"])
        self.assertIsNone(by_name["seat_pass_ratio"]["value"])
        self.assertTrue(by_name["seat_t_c_min"]["omitted"])


if __name__ == "__main__":
    unittest.main()
