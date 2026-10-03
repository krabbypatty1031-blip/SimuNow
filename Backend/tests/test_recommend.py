"""Structured recommendation cards. No model API and no invented savings."""

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
        "retrofitQuote": "待报价",
        "assumptions": ["比赛演示假设，非真实电价"],
    }
    row.update(overrides)
    return row


class RecommendTests(unittest.TestCase):
    def test_supply_height_change_cites_both_l2_runs(self):
        from simunow_worker.models.recommend import classify_cards

        low = _candidate(
            name="低送风口",
            runID="11111111-1111-1111-1111-111111111111",
            supplyZ0=2.10,
            supplyZ1=2.28,
            seatTMinC=24.21,
        )
        high = _candidate(
            name="默认送风口",
            runID="22222222-2222-2222-2222-222222222222",
            l1RunID="44444444-4444-4444-4444-444444444444",
            seatTMinC=24.43,
        )
        cards = classify_cards([low, high])
        comfort = next(card for card in cards if card["kind"] == "comfort")
        self.assertTrue(comfort["qualityPassed"])
        self.assertIn(low["runID"], comfort["citedRunIDs"])
        self.assertIn(high["runID"], comfort["citedRunIDs"])
        blob = json.dumps(cards, ensure_ascii=False)
        self.assertNotIn("全局最优", blob)
        self.assertNotIn("满意率", blob)

    def test_no_quality_passed_field_is_explanation_only(self):
        from simunow_worker.models.recommend import classify_cards

        failed = _candidate(quality="failed", seatPassRatio=None, seatPassCount=None, seatEvalCount=None)
        cards = classify_cards([failed])
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0]["kind"], "explanation")
        self.assertNotIn("推荐方案", json.dumps(cards, ensure_ascii=False))
        self.assertEqual(cards[0]["citedRunIDs"], [failed["runID"]])

    def test_retrofit_without_quote_omits_payback(self):
        from simunow_worker.models.recommend import classify_cards

        low = _candidate(runID="11111111-1111-1111-1111-111111111111", supplyZ0=2.10, supplyZ1=2.28, seatTMinC=24.21, dayCost=12.0)
        high = _candidate(
            runID="22222222-2222-2222-2222-222222222222",
            l1RunID="44444444-4444-4444-4444-444444444444",
            seatPassRatio=0.75,
            seatPassCount=6,
            seatTMinC=24.43,
            dayCost=18.0,
            dayEnergyKWh=15.0,
        )
        cards = classify_cards([low, high])
        retrofit = next(card for card in cards if card["kind"] == "retrofit")
        self.assertEqual(retrofit["quoteStatus"], "待报价")
        self.assertIn("待报价", retrofit["detail"])
        self.assertNotIn("payback", retrofit)
        self.assertTrue(retrofit["assumptions"])
        kinds = [card["kind"] for card in cards]
        self.assertLess(kinds.index("comfort"), kinds.index("operation"))
        self.assertLess(kinds.index("operation"), kinds.index("retrofit"))

    def test_mixed_basis_is_explanation_and_refuses_export(self):
        from simunow_worker.models.recommend import can_export_recommendation, classify_cards

        eight = _candidate(runID="11111111-1111-1111-1111-111111111111", seatPassRatio=1)
        ten_basis = dict(eight["basis"])
        ten_basis["occupantCount"] = 10
        ten = _candidate(
            name="10人",
            runID="22222222-2222-2222-2222-222222222222",
            basis=ten_basis,
            seatPassRatio=1,
        )
        cards = classify_cards([eight, ten])
        self.assertEqual(len(cards), 1)
        self.assertEqual(cards[0]["kind"], "explanation")
        self.assertIn("口径不同", cards[0]["detail"])
        self.assertIn("不能作为有效推荐", cards[0]["detail"])
        self.assertFalse(can_export_recommendation([eight, ten]))
        self.assertTrue(can_export_recommendation([eight, _candidate(runID="22222222-2222-2222-2222-222222222222", supplyZ0=2.10, supplyZ1=2.28, seatTMinC=24.21)]))

    def test_evidence_copies_candidate_numbers_and_schema_keys(self):
        from simunow_worker.models.recommend import build_evidence

        low = _candidate(supplyZ0=2.10, supplyZ1=2.28, seatTMinC=24.21, seatPassRatio=1, dayCost=12.0, dayEnergyKWh=10.0)
        evidence = build_evidence([low])
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        for key in schema["required"]:
            self.assertIn(key, evidence)
        self.assertEqual(evidence["schemaVersion"], 1)
        self.assertEqual(evidence["candidates"][0]["runID"], low["runID"])
        self.assertEqual(evidence["candidates"][0]["inputHash"], low["inputHash"])
        self.assertEqual(evidence["candidates"][0]["seatPassRatio"], 1)
        self.assertEqual(evidence["candidates"][0]["dayCost"], 12.0)
        self.assertEqual(evidence["candidates"][0]["dayEnergyKWh"], 10.0)
        self.assertNotIn("payback", json.dumps(evidence))
        self.assertNotIn("37", json.dumps(evidence))
