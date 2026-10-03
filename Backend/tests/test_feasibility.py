"""L2 seat coverage is a model gate, not a measured satisfaction rate.

Synthetic seats only: no OpenFOAM. A missing or failed field omits the
ratio. Out-of-domain seats leave the denominator instead of counting as
failures. Ratio 0 means every evaluated seat missed a gate.

Sampler omissions (`samples.json` `omitted_seats`) are ids and reasons,
not public seat rows. They still have to be named on the ratio reason.
"""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

from simunow_worker.l2_runner import _seat_rows
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

    def test_context_omitted_seats_are_named_and_stay_off_the_public_array(self):
        # Real samples keep {id, reason} beside seats. Stuffing that stub
        # into seatSamples would violate the schema (tC/uMag required).
        context = {
            "pipelineCompleted": True,
            "qualityDetail": dict(PASSED_QUALITY),
            "seatSamples": [
                {"id": "S1", "x": 1, "y": 1, "z": 1.1, "tC": 24.5, "uMag": 0.05},
                {"id": "S2", "x": 2, "y": 2, "z": 1.1, "tC": 25.5, "uMag": 0.20},
            ],
            "omittedSeats": [{"id": "S9", "reason": "not_in_fluid"}],
        }
        result = evaluate_l2(self._identity(), OFFICE, context)
        self.assertEqual([seat["id"] for seat in result["seatSamples"]], ["S1", "S2"])
        for seat in result["seatSamples"]:
            self.assertIn("tC", seat)
            self.assertIn("uMag", seat)
        by_name = _by_name(result["metrics"])
        self.assertEqual(by_name["seat_eval_count"]["value"], 2)
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        reason = by_name["seat_pass_ratio"]["reason"]
        self.assertIn("S9", reason)
        self.assertIn("不计入分母", reason)
        self.assertNotIn("S9", [seat["id"] for seat in result["seatSamples"]])

    def test_only_omitted_seats_are_named_without_inventing_ratio_zero(self):
        # Quality passed, but every seat was outside the fluid. No evaluated
        # seat means the ratio stays omitted. Naming the ids is required;
        # 0% would claim they were evaluated and failed.
        context = {
            "pipelineCompleted": True,
            "qualityDetail": dict(PASSED_QUALITY),
            "seatSamples": None,
            "omittedSeats": [
                {"id": "S9", "reason": "not_in_fluid"},
                {"id": "S8", "reason": "not_in_fluid"},
            ],
        }
        result = evaluate_l2(self._identity(), OFFICE, context)
        self.assertFalse(result["seatSamples"])
        by_name = _by_name(result["metrics"])
        ratio = by_name["seat_pass_ratio"]
        self.assertTrue(ratio["omitted"])
        self.assertIsNone(ratio["value"])
        self.assertNotEqual(ratio["value"], 0)
        self.assertIn("S9", ratio["reason"])
        self.assertIn("S8", ratio["reason"])
        self.assertIn("不计入分母", ratio["reason"])
        self.assertNotIn("no quality-passed seat samples", ratio["reason"])


class SeparateOmissionTests(unittest.TestCase):
    def test_omitted_seat_argument_leaves_the_denominator_and_names_the_id(self):
        by_name = _by_name(
            feasibility_metrics(
                [dict(row) for row in IN_BAND[:3]],
                quality_passed=True,
                omitted_seats=[{"id": "S9", "reason": "not_in_fluid"}],
            )
        )
        self.assertEqual(by_name["seat_eval_count"]["value"], 3)
        self.assertEqual(by_name["seat_pass_count"]["value"], 3)
        self.assertEqual(by_name["seat_pass_ratio"]["value"], 1.0)
        self.assertIn("S9", by_name["seat_pass_ratio"]["reason"])
        self.assertIn("不计入分母", by_name["seat_pass_ratio"]["reason"])
        self.assertNotEqual(by_name["worst_seat_id"]["reason"], "S9")

    def test_no_eval_seats_with_omissions_omits_ratio_and_names_ids(self):
        metrics = feasibility_metrics(
            None,
            quality_passed=True,
            omitted_seats=[{"id": "S9", "reason": "not_in_fluid"}],
        )
        ratio = _by_name(metrics)["seat_pass_ratio"]
        self.assertTrue(ratio["omitted"])
        self.assertIsNone(ratio["value"])
        self.assertNotEqual(ratio["value"], 0)
        self.assertIn("S9", ratio["reason"])
        self.assertIn("不计入分母", ratio["reason"])
        for metric in metrics:
            self.assertTrue(metric["omitted"], metric["name"])
            self.assertIsNone(metric["value"], metric["name"])


# Public seat rows require tC/uMag. Sampler omissions are a side list.
_CONTRACT_SEAT_KEYS = {"id", "x", "y", "z", "tC", "uMag", "lowSpeedAbsoluteError", "pmv", "ppd"}


class RunnerOmittedSeatMappingTests(unittest.TestCase):
    """samples.json → evaluate_l2 without OpenFOAM."""

    def _write_samples(self, run_dir: Path, *, seats: list[dict], omitted: list[dict]) -> None:
        (run_dir / "samples.json").write_text(
            json.dumps({"seats": seats, "omitted_seats": omitted}, ensure_ascii=False),
            encoding="utf-8",
        )
        (run_dir / "quality.json").write_text(
            json.dumps(
                {
                    "checkMesh": "ok",
                    "solver_end": True,
                    "monitors": {"stable": True},
                    "mass": {"relative_error": 0.001, "gate": 0.01},
                    "energy": {"relative_error": 0.004, "gate": 0.05},
                }
            ),
            encoding="utf-8",
        )

    def _identity(self):
        return {"runID": str(uuid4()), "scenarioID": str(uuid4()), "inputHash": "omitted-seat-map"}

    def test_seat_rows_stay_contract_valid_and_omitted_ids_reach_feasibility(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            self._write_samples(
                run_dir,
                seats=[
                    {"id": "S1", "x": 1.0, "y": 1.5, "z": 1.1, "T_C": 24.5, "U_mag": 0.05},
                ],
                omitted=[{"id": "S9", "omitted": True, "reason": "not_in_fluid"}],
            )
            rows = _seat_rows(run_dir)
            self.assertEqual([row["id"] for row in rows], ["S1"])
            for row in rows:
                self.assertTrue(_CONTRACT_SEAT_KEYS.issuperset(row))
                self.assertIsInstance(row["tC"], float)
                self.assertIsInstance(row["uMag"], float)
            self.assertNotIn("S9", [row["id"] for row in rows])

            # Imported inside the test so a missing helper fails this case only.
            from simunow_worker.l2_runner import passed_field_context

            context = passed_field_context(run_dir, OFFICE)
            self.assertEqual([row["id"] for row in context["seatSamples"]], ["S1"])
            self.assertEqual(context["omittedSeats"][0]["id"], "S9")
            self.assertEqual(context["omittedSeats"][0]["reason"], "not_in_fluid")
            result = evaluate_l2(self._identity(), OFFICE, context)
            self.assertEqual([seat["id"] for seat in result["seatSamples"]], ["S1"])
            for seat in result["seatSamples"]:
                self.assertIn("tC", seat)
                self.assertIn("uMag", seat)
            reason = _by_name(result["metrics"])["seat_pass_ratio"]["reason"]
            self.assertIn("S9", reason)
            self.assertIn("不计入分母", reason)

    def test_samples_with_only_omitted_seats_name_ids_and_do_not_invent_zero(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp)
            self._write_samples(
                run_dir,
                seats=[],
                omitted=[{"id": "S9", "omitted": True, "reason": "not_in_fluid"}],
            )
            # An empty fluid list is not a public seat array of stubs.
            self.assertIsNone(_seat_rows(run_dir))
            from simunow_worker.l2_runner import passed_field_context

            result = evaluate_l2(self._identity(), OFFICE, passed_field_context(run_dir, OFFICE))
            self.assertFalse(result["seatSamples"])
            ratio = _by_name(result["metrics"])["seat_pass_ratio"]
            self.assertTrue(ratio["omitted"])
            self.assertIsNone(ratio["value"])
            self.assertNotEqual(ratio["value"], 0)
            self.assertIn("S9", ratio["reason"])
            self.assertNotIn("no quality-passed seat samples", ratio["reason"])


if __name__ == "__main__":
    unittest.main()
