"""Typical-year calendar day. Missing weather is still 15 July; 29 Feb is refused."""

from __future__ import annotations

import unittest

from simunow_worker.models.weather import is_valid_typical_year_day, mmdd, resolved_weather


class WeatherDayTests(unittest.TestCase):
    def test_typical_year_rejects_leap_day(self):
        self.assertTrue(is_valid_typical_year_day(7, 15))
        self.assertTrue(is_valid_typical_year_day(2, 28))
        self.assertFalse(is_valid_typical_year_day(2, 29))
        self.assertFalse(is_valid_typical_year_day(4, 31))

    def test_missing_weather_resolves_to_july_15(self):
        self.assertEqual(resolved_weather({}), (7, 15))
        self.assertEqual(resolved_weather({"weather": {"month": 1, "day": 15}}), (1, 15))
        self.assertEqual(mmdd(1, 15), "01-15")

    def test_invalid_day_is_rejected(self):
        with self.assertRaises(ValueError):
            resolved_weather({"weather": {"month": 2, "day": 29}})


if __name__ == "__main__":
    unittest.main()
