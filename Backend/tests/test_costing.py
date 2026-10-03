"""ADR-014 representative-day tariff. No annual kWh and no payback."""

from __future__ import annotations

import unittest

from simunow_worker.models.costing import DEMO_TARIFF, representative_day_cost


class CostAccountingTests(unittest.TestCase):
    def test_demo_tariff_locks_office_day_energy_and_hkd_millis(self):
        self.assertEqual(DEMO_TARIFF["pricePerKWh"], 1.2)
        self.assertEqual(DEMO_TARIFF["currency"], "HKD")
        self.assertEqual(DEMO_TARIFF["source"], "assumed")
        self.assertEqual(DEMO_TARIFF["reference"], "比赛演示假设，非真实电价")
        day = representative_day_cost(1033.112, "08:00", "18:00", DEMO_TARIFF)
        self.assertEqual(f"{day['energy_kwh']:.5f}", "10.33112")
        self.assertEqual(f"{day['cost']:.3f}", "12.397")
        self.assertEqual(day["currency"], "HKD")
        self.assertFalse(day["energy_omitted"])
        self.assertFalse(day["cost_omitted"])
        self.assertEqual(day["occupied_hours"], 10)
        self.assertEqual(day["retrofit_quote"], "待报价")

    def test_missing_tariff_omits_cost_day(self):
        day = representative_day_cost(1033.112, "08:00", "18:00", None)
        self.assertIsNone(day["cost"])
        self.assertTrue(day["cost_omitted"])
        self.assertIsNone(day["currency"])
        self.assertEqual(f"{day['energy_kwh']:.5f}", "10.33112")
        self.assertNotEqual(day["cost"], 0)

    def test_missing_electric_power_omits_energy_and_cost(self):
        day = representative_day_cost(None, "08:00", "18:00", DEMO_TARIFF)
        self.assertIsNone(day["energy_kwh"])
        self.assertIsNone(day["cost"])
        self.assertTrue(day["energy_omitted"])
        self.assertTrue(day["cost_omitted"])
        self.assertNotEqual(day["energy_kwh"], 0)
        self.assertNotEqual(day["cost"], 0)

    def test_result_has_no_valued_annual_or_payback(self):
        day = representative_day_cost(1033.112, "08:00", "18:00", DEMO_TARIFF)
        for key in ("annual_kwh", "payback_years", "annualKWh", "paybackYears"):
            self.assertNotIn(key, day)
            self.assertIsNone(day.get(key))
        self.assertEqual(day["retrofit_quote"], "待报价")

    def test_savings_are_two_l1_costs_and_hidden_on_basis_mismatch(self):
        from simunow_worker.models.costing import savings_hkd

        low = representative_day_cost(1000, "08:00", "18:00", DEMO_TARIFF)
        high = representative_day_cost(1500, "08:00", "18:00", DEMO_TARIFF)
        saved = savings_hkd(high, low, basis_mismatch=None)
        self.assertEqual(f"{saved:.3f}", "6.000")
        self.assertEqual(saved, high["cost"] - low["cost"])
        self.assertIsNone(savings_hkd(high, low, basis_mismatch="口径不同（人数）"))
        self.assertNotEqual(saved, 1500 * 0.1)


if __name__ == "__main__":
    unittest.main()
