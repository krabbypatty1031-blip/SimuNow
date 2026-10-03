import json
import unittest
from pathlib import Path

from simunow_worker.models.l1_accounting import evaluate_l1, schedule_hash
from simunow_worker.models.task import TaskProtocolError

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]
IDENTITY = {
    "runID": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    "scenarioID": "cccccccc-cccc-cccc-cccc-cccccccccccc",
    "inputHash": "snap",
}


class L1AccountingTests(unittest.TestCase):
    def test_missing_weather_omits_loads(self):
        result = evaluate_l1(IDENTITY, OFFICE, {"weatherPath": None, "weatherHash": None, "coolingLoadW": None})
        cool = next(item for item in result["metrics"] if item["name"] == "q_cool_w")
        elec = next(item for item in result["metrics"] if item["name"] == "p_elec_w")
        annual = next(item for item in result["metrics"] if item["name"] == "annual_kwh")
        self.assertTrue(cool["omitted"])
        self.assertIsNone(cool["value"])
        self.assertTrue(elec["omitted"])
        self.assertIsNone(elec["value"])
        self.assertTrue(annual["omitted"])
        self.assertIsNone(result["weatherPath"])

    def test_electricity_is_cooling_over_cop(self):
        result = evaluate_l1(
            IDENTITY,
            OFFICE,
            {
                "weatherPath": "weather/CHN_Hong.Kong.SAR.450070_CityUHK.epw",
                "weatherHash": "epw-hash",
                "coolingLoadW": 6334.87,
            },
        )
        cool = next(item for item in result["metrics"] if item["name"] == "q_cool_w")
        elec = next(item for item in result["metrics"] if item["name"] == "p_elec_w")
        self.assertEqual(cool["value"], 6334.87)
        self.assertAlmostEqual(elec["value"], 6334.87 / 3.0)
        self.assertEqual(elec["method"], "equivalent_ideal_loads")
        self.assertEqual(result["period"]["kind"], "representative_day")
        self.assertEqual(result["weatherHash"], "epw-hash")
        self.assertEqual(result["supplyTemperatureC"], 16)
        self.assertEqual(result["setpointC"], 26)

    def test_absolute_weather_path_is_rejected(self):
        with self.assertRaises(TaskProtocolError) as raised:
            evaluate_l1(
                IDENTITY,
                OFFICE,
                {"weatherPath": "/Users/krabbypatty/weather.epw", "weatherHash": "h", "coolingLoadW": 1},
            )
        self.assertEqual(raised.exception.code, TaskProtocolError.unsafe_snapshot_path)

    def test_office_schedule_enters_l1_with_hash(self):
        digest = schedule_hash(OFFICE)
        result = evaluate_l1(
            IDENTITY,
            OFFICE,
            {
                "weatherPath": "weather/HK.epw",
                "weatherHash": "epw-hash",
                "coolingLoadW": 900,
                "scheduleHash": digest,
            },
        )
        self.assertEqual(result["schedule"]["kind"], "occupied_hours")
        self.assertEqual(result["schedule"]["start"], "08:00")
        self.assertEqual(result["schedule"]["end"], "18:00")
        self.assertEqual(result["hvacSchedule"]["start"], "08:00")
        self.assertEqual(result["scheduleHash"], digest)
        self.assertNotEqual(result["scheduleHash"], result["weatherHash"])

    def test_missing_schedule_does_not_invent_hours(self):
        draft = json.loads(json.dumps(OFFICE))
        draft["occupancy"].pop("schedule", None)
        draft["hvac"].pop("schedule", None)
        result = evaluate_l1(
            IDENTITY,
            draft,
            {"weatherPath": "weather/HK.epw", "weatherHash": "h", "coolingLoadW": 1},
        )
        self.assertIsNone(result["schedule"])
        self.assertIsNone(result["hvacSchedule"])
        self.assertIsNone(result["scheduleHash"])

    def test_wrong_schedule_hash_is_rejected(self):
        with self.assertRaises(TaskProtocolError) as raised:
            evaluate_l1(
                IDENTITY,
                OFFICE,
                {
                    "weatherPath": "weather/HK.epw",
                    "weatherHash": "h",
                    "coolingLoadW": 1,
                    "scheduleHash": "not-the-schedule",
                },
            )
        self.assertEqual(raised.exception.code, TaskProtocolError.hash_mismatch)


if __name__ == "__main__":
    unittest.main()
