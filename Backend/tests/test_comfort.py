"""ISO 7730 comfort: evaluated only with complete inputs, never PMV=0.

PMV/PPD follow the ISO 7730 Annex D normative algorithm. Anchors, in order
of authority:
- published output of the same Annex D program (met 1.4, clo 0.5, RH 50 %):
  tdb=tr=25 at vr 0.22 -> PMV 0.17 / PPD 5.6, at vr 0.1 -> PMV 0.41 / PPD 8.5
- ISO 7730 Table 2 / Figure 1: PPD(0) = 5 %, PPD(+-0.5) = 10 %, PPD(+-1) = 26 %
Missing or out-of-range inputs are not evaluable; the result carries a reason
instead of a fabricated value.
"""

from __future__ import annotations

import unittest

from simunow_worker.models.comfort import NotEvaluable, comfort_metrics, pmv_ppd, ppd_from_pmv
from simunow_worker.models.l2_accounting import evaluate_l2

OFFICE = {
    "hvac": {"supplyTemperatureC": {"value": 16}, "setpointC": {"value": 26}},
}

SEATS = [
    {"id": "S1", "x": 1.5, "y": 1.5, "z": 1.1, "tC": 24.5, "uMag": 0.05},
    {"id": "S2", "x": 4.5, "y": 4.5, "z": 1.1, "tC": 25.5, "uMag": 0.20},
]

INPUTS = {"mrtC": 25.0, "rhPct": 50.0, "clo": 0.5, "met": 1.2}


class PmvPpdTests(unittest.TestCase):
    def test_annex_d_program_anchors(self):
        # Published output of the Annex D algorithm at met 1.4, clo 0.5, RH 50.
        result = pmv_ppd(t_air_c=25, t_mrt_c=25, rh_pct=50, clo=0.5, met=1.4, v_m_s=0.22)
        self.assertEqual(round(result["pmv"], 2), 0.17)
        self.assertEqual(round(result["ppd"], 1), 5.6)
        result = pmv_ppd(t_air_c=25, t_mrt_c=25, rh_pct=50, clo=0.5, met=1.4, v_m_s=0.1)
        self.assertEqual(round(result["pmv"], 2), 0.41)
        self.assertEqual(round(result["ppd"], 1), 8.5)

    def test_table2_ppd_values(self):
        # ISO 7730 Table 2 / Figure 1: 5 %, 10 %, 10 %, 26 %, 26 %.
        self.assertAlmostEqual(ppd_from_pmv(0.0), 5.0, delta=0.3)
        self.assertAlmostEqual(ppd_from_pmv(0.5), 10.0, delta=0.3)
        self.assertAlmostEqual(ppd_from_pmv(-0.5), 10.0, delta=0.3)
        self.assertAlmostEqual(ppd_from_pmv(1.0), 26.0, delta=0.3)
        self.assertAlmostEqual(ppd_from_pmv(-1.0), 26.0, delta=0.3)

    def test_pmv_rises_with_air_temperature(self):
        colder = pmv_ppd(t_air_c=22, t_mrt_c=22, rh_pct=50, clo=0.5, met=1.2, v_m_s=0.1)
        neutral = pmv_ppd(t_air_c=25, t_mrt_c=25, rh_pct=50, clo=0.5, met=1.2, v_m_s=0.1)
        warmer = pmv_ppd(t_air_c=27, t_mrt_c=27, rh_pct=50, clo=0.5, met=1.2, v_m_s=0.1)
        self.assertLess(colder["pmv"], neutral["pmv"])
        self.assertLess(neutral["pmv"], warmer["pmv"])

    def test_out_of_range_inputs_are_not_evaluable(self):
        # The standard's applicability: air speed <= 1 m/s, clo <= 2,
        # met 0.8..4, air and radiant temperature within model limits,
        # pa <= 2700 Pa, and PMV only between -2 and +2.
        probes = (
            (dict(v_m_s=1.5), "air speed"),
            (dict(clo=2.5), "clothing"),
            (dict(met=0.5), "metabolic"),
            (dict(t_air_c=35.0), "air temperature"),
            (dict(t_mrt_c=45.0), "radiant temperature"),
            (dict(rh_pct=120.0), "relative humidity"),
            (dict(t_air_c=30.0, rh_pct=100.0), "water vapour pressure"),
        )
        for kwargs, fragment in probes:
            with self.subTest(fragment=fragment):
                base = dict(t_air_c=25.0, t_mrt_c=25.0, rh_pct=50.0, clo=0.5, met=1.2, v_m_s=0.1)
                base.update(kwargs)
                with self.assertRaises(NotEvaluable) as raised:
                    pmv_ppd(**base)
                self.assertIn(fragment, str(raised.exception))

    def test_pmv_beyond_two_sigma_of_scale_is_not_evaluable(self):
        # Clause 4: the index is only defined for PMV between -2 and +2;
        # a cold extreme must not return a fabricated vote.
        with self.assertRaises(NotEvaluable) as raised:
            pmv_ppd(t_air_c=10.0, t_mrt_c=10.0, rh_pct=50.0, clo=0.0, met=0.8, v_m_s=1.0)
        self.assertIn("pmv", str(raised.exception))


class ComfortMetricsTests(unittest.TestCase):
    def test_complete_inputs_annotate_seats_and_report_aggregates(self):
        seats, metrics = comfort_metrics([dict(seat) for seat in SEATS], INPUTS)
        self.assertEqual(len(seats), 2)
        self.assertIn("pmv", seats[0])
        self.assertIn("ppd", seats[0])
        # Same air speed: the cooler seat must get the lower PMV. (At the
        # office seats above the speeds differ, and a faster stream can
        # outweigh 1 C of air temperature - which is real physics, not a bug.)
        calm = [
            dict(SEATS[0], tC=24.5, uMag=0.10),
            dict(SEATS[1], tC=25.5, uMag=0.10),
        ]
        calm_rows, _ = comfort_metrics(calm, INPUTS)
        self.assertLess(calm_rows[0]["pmv"], calm_rows[1]["pmv"])
        by_name = {metric["name"]: metric for metric in metrics}
        self.assertEqual(by_name["seat_pmv_min"]["method"], "iso7730_pmv")
        self.assertEqual(by_name["seat_pmv_min"]["fidelity"], "l2")
        self.assertFalse(by_name["seat_pmv_min"]["omitted"])
        self.assertAlmostEqual(by_name["seat_pmv_min"]["value"], min(row["pmv"] for row in seats), places=9)
        self.assertAlmostEqual(by_name["seat_pmv_max"]["value"], max(row["pmv"] for row in seats), places=9)
        self.assertAlmostEqual(by_name["seat_ppd_max"]["value"], max(row["ppd"] for row in seats), places=9)

    def test_missing_inputs_omit_metrics_with_reason_and_never_zero(self):
        seats, metrics = comfort_metrics([dict(seat) for seat in SEATS], None)
        self.assertEqual(len(seats), 2)
        for row in seats:
            self.assertNotIn("pmv", row)
            self.assertNotIn("ppd", row)
        by_name = {metric["name"]: metric for metric in metrics}
        for name in ("seat_pmv_min", "seat_pmv_max", "seat_ppd_max"):
            metric = by_name[name]
            self.assertTrue(metric["omitted"])
            self.assertIsNone(metric["value"])
            self.assertNotEqual(metric["value"], 0)
            self.assertIn("missing", metric["reason"])
        for key in ("mrtC", "rhPct", "clo", "met"):
            self.assertIn(key, by_name["seat_pmv_min"]["reason"])

    def test_partial_inputs_are_disclosed_in_the_reason(self):
        partial = dict(INPUTS, mrtC=None)
        seats, metrics = comfort_metrics([dict(seat) for seat in SEATS], partial)
        by_name = {metric["name"]: metric for metric in metrics}
        self.assertTrue(by_name["seat_pmv_min"]["omitted"])
        self.assertIn("mrtC", by_name["seat_pmv_min"]["reason"])

    def test_out_of_range_seat_speeds_are_excluded_and_disclosed(self):
        seats = [dict(SEATS[0]), dict(SEATS[1], uMag=1.5)]
        rows, metrics = comfort_metrics(seats, INPUTS)
        by_name = {metric["name"]: metric for metric in metrics}
        # One seat evaluated: aggregates stay real, the exclusion is noted.
        self.assertFalse(by_name["seat_pmv_min"]["omitted"])
        self.assertIsNotNone(by_name["seat_pmv_min"]["value"])
        self.assertIn("1 of 2", by_name["seat_pmv_min"]["reason"])
        self.assertIn("S2", by_name["seat_pmv_min"]["reason"])
        # The out-of-range seat carries no pmv of its own.
        for row in rows:
            if row["id"] == "S2":
                self.assertNotIn("pmv", row)


class EvaluateL2ComfortTests(unittest.TestCase):
    def _identity(self):
        from uuid import uuid4

        return {"runID": str(uuid4()), "scenarioID": str(uuid4()), "inputHash": "comfort-test"}

    def _quality(self, **context_extra):
        quality = {
            "pipelineCompleted": True,
            "qualityDetail": {
                "checkMesh": "ok",
                "solverEnded": True,
                "monitorsStable": True,
                "massRelativeError": 0.001,
                "massGate": 0.01,
                "energyRelativeError": 0.004,
                "energyGate": 0.05,
            },
            "seatSamples": [dict(seat) for seat in SEATS],
        }
        quality.update(context_extra)
        return quality

    def test_result_carries_omitted_comfort_metrics_with_reason(self):
        result = evaluate_l2(self._identity(), OFFICE, self._quality(comfortInputs=None))
        by_name = {metric["name"]: metric for metric in result["metrics"]}
        pmv_min = by_name["seat_pmv_min"]
        self.assertTrue(pmv_min["omitted"])
        self.assertIsNone(pmv_min["value"])
        self.assertIn("missing", pmv_min["reason"])
        self.assertIn("mrtC", pmv_min["reason"])
        # Seats stay unannotated; nothing becomes PMV=0.
        for row in result["seatSamples"]:
            self.assertNotIn("pmv", row)

    def test_result_with_complete_comfort_inputs_evaluates_pmv(self):
        result = evaluate_l2(
            self._identity(),
            OFFICE,
            self._quality(comfortInputs=INPUTS),
        )
        by_name = {metric["name"]: metric for metric in result["metrics"]}
        self.assertFalse(by_name["seat_pmv_min"]["omitted"])
        self.assertIsNotNone(by_name["seat_pmv_min"]["value"])
        self.assertIn("pmv", result["seatSamples"][0])


if __name__ == "__main__":
    unittest.main()
