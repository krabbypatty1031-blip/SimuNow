"""Pair diff for the AI report (ADR-021). No classifier cards, no model API, no invented savings.

Subtraction happens in code so every delta the AI narrates is already evidence.
"""

from __future__ import annotations

import json
import unittest
from pathlib import Path

SCHEMA = Path(__file__).resolve().parents[2] / "Protocols" / "Schemas" / "report-evidence.schema.json"


def _candidate(**overrides):
    row = {
        "name": "方案",
        "runID": "11111111-1111-1111-1111-111111111111",
        "l1RunID": "33333333-3333-3333-3333-333333333333",
        "inputHash": "hash-a",
        "scenarioID": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        "quality": "passed",
        "basis": {
            "occupantCount": 8,
            "occupiedStart": "08:00",
            "occupiedEnd": "18:00",
            "setpointC": 26,
            "supplyTemperatureC": 16,
        },
        "supplyZ0": 2.48,
        "supplyZ1": 2.66,
        "seatTMinC": 24.43,
        "seatPassRatio": 1,
        "seatPassCount": 8,
        "seatEvalCount": 8,
        "dayCost": 12.0,
        "dayEnergyKWh": 10.0,
        "currency": "HKD",
        "assumptions": ["比赛演示假设，非真实电价"],
    }
    row.update(overrides)
    return row


class PairDiffTests(unittest.TestCase):
    def test_supply_height_change_builds_sentence_and_deltas(self):
        from simunow_worker.models.recommend import pair_diff

        low = _candidate(
            name="低送风口",
            runID="11111111-1111-1111-1111-111111111111",
            supplyZ0=2.10,
            supplyZ1=2.28,
            seatTMinC=24.21,
            dayCost=12.0,
            dayEnergyKWh=10.0,
        )
        high = _candidate(
            name="默认送风口",
            runID="22222222-2222-2222-2222-222222222222",
            l1RunID="44444444-4444-4444-4444-444444444444",
            seatTMinC=24.43,
            dayCost=18.0,
            dayEnergyKWh=15.0,
        )
        diff = pair_diff([low, high])
        self.assertEqual(diff["firstName"], "低送风口")
        self.assertEqual(diff["secondName"], "默认送风口")
        # The user-facing sentence carries the exact heights the AI copies.
        z0 = next(change for change in diff["inputChanges"] if change["field"] == "supplyZ0M")
        self.assertEqual(z0["fromValue"], 2.10)
        self.assertEqual(z0["toValue"], 2.48)
        self.assertIn("出风口下沿从 2.10 m 改为 2.48 m", z0["sentence"])
        # Same basis, so no mismatch sentence.
        self.assertIsNone(diff["basisMismatchReason"])
        # Comfort delta is second - first, half-up to two decimals.
        seat = next(delta for delta in diff["resultDeltas"] if delta["field"] == "seatTMinC")
        self.assertEqual(seat["dimension"], "comfort")
        self.assertEqual(seat["first"], 24.21)
        self.assertEqual(seat["second"], 24.43)
        self.assertEqual(seat["delta"], 0.22)
        # Energy rows keep the dimension the report groups by.
        day_cost = next(delta for delta in diff["resultDeltas"] if delta["field"] == "dayCost")
        self.assertEqual(day_cost["dimension"], "energy")
        self.assertEqual(day_cost["delta"], 6.0)
        blob = json.dumps(diff, ensure_ascii=False)
        self.assertNotIn("满意率", blob)
        self.assertNotIn("payback", blob)

    def test_single_scheme_has_no_diff(self):
        from simunow_worker.models.recommend import pair_diff

        self.assertIsNone(pair_diff([_candidate()]))
        self.assertIsNone(pair_diff([]))

    def test_delta_rounds_half_up_and_avoids_negative_zero(self):
        from simunow_worker.models.recommend import _delta

        # Second - first, half-up two decimals, away from zero on ties.
        self.assertEqual(_delta(24.435, 24.445), 0.01)
        self.assertEqual(_delta(24.435, 24.425), -0.01)
        self.assertEqual(_delta(1.0, 0.999999999), 0.0)  # tiny negative rounds to 0, not -0.0
        self.assertIsNone(_delta(1.0, None))
        self.assertIsNone(_delta(None, 1.0))

    def test_basis_mismatch_reason_names_the_lever(self):
        from simunow_worker.models.recommend import pair_diff

        eight = _candidate(runID="11111111-1111-1111-1111-111111111111")
        ten_basis = dict(eight["basis"])
        ten_basis["occupantCount"] = 10
        ten = _candidate(
            name="10人",
            runID="22222222-2222-2222-2222-222222222222",
            basis=ten_basis,
        )
        diff = pair_diff([eight, ten])
        self.assertEqual(diff["basisMismatchReason"], "口径不同（人数）")
        # The lever itself stays in the diff; the AI narrates it as input.
        occupant = next(change for change in diff["inputChanges"] if change["field"] == "occupantCount")
        self.assertIn("人数从 8.00 人改为 10.00 人", occupant["sentence"])

    def test_occupied_hours_change_is_sentence_only(self):
        from simunow_worker.models.recommend import pair_diff

        early = _candidate(runID="11111111-1111-1111-1111-111111111111")
        later_basis = dict(early["basis"])
        later_basis["occupiedStart"] = "09:00"
        later = _candidate(
            runID="22222222-2222-2222-2222-222222222222",
            basis=later_basis,
        )
        diff = pair_diff([early, later])
        hours = next(change for change in diff["inputChanges"] if change["field"] == "occupiedHours")
        self.assertIsNone(hours["fromValue"])
        self.assertIsNone(hours["toValue"])
        self.assertIn("使用时间从 08:00–18:00 改为 09:00–18:00", hours["sentence"])


class EvidenceTests(unittest.TestCase):
    def test_evidence_carries_pair_diff_and_schema_keys(self):
        from simunow_worker.models.recommend import build_evidence

        low = _candidate(supplyZ0=2.10, supplyZ1=2.28, seatTMinC=24.21, seatPassRatio=1, dayCost=12.0, dayEnergyKWh=10.0)
        high = _candidate(
            runID="22222222-2222-2222-2222-222222222222",
            l1RunID="44444444-4444-4444-4444-444444444444",
            seatTMinC=24.43,
            dayCost=18.0,
            dayEnergyKWh=15.0,
        )
        evidence = build_evidence([low, high])
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        for key in schema["required"]:
            self.assertIn(key, evidence)
        self.assertEqual(evidence["schemaVersion"], 1)
        # The classifier card era is over: cards must be gone, pairDiff present.
        self.assertNotIn("cards", evidence)
        self.assertEqual(evidence["pairDiff"]["firstName"], low["name"])
        self.assertEqual(evidence["candidates"][0]["runID"], low["runID"])
        self.assertEqual(evidence["candidates"][0]["inputHash"], low["inputHash"])
        self.assertEqual(evidence["candidates"][0]["seatPassRatio"], 1)
        self.assertEqual(evidence["candidates"][0]["dayCost"], 12.0)
        self.assertEqual(evidence["candidates"][0]["dayEnergyKWh"], 10.0)
        self.assertEqual(evidence["candidates"][0]["occupiedDaysPerYear"], 365)
        self.assertEqual(evidence["candidates"][0]["annualEnergyKWh"], 3650.0)
        self.assertEqual(evidence["candidates"][0]["annualCost"], 4380.0)
        self.assertNotIn("payback", json.dumps(evidence))
        self.assertNotIn("37", json.dumps(evidence))

    def test_single_scheme_evidence_has_null_pair_diff(self):
        from simunow_worker.models.recommend import build_evidence

        evidence = build_evidence([_candidate()])
        self.assertIsNone(evidence["pairDiff"])
        for key in ("firstName", "secondName", "inputChanges", "resultDeltas"):
            self.assertNotIn(key, evidence)
