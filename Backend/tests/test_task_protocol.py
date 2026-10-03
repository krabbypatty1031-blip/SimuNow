import json
import tempfile
import unittest
from pathlib import Path

from simunow_worker.models.task import (
    EventStream,
    TaskProtocolError,
    has_execute_bit,
    parse_result,
    sha256_hex,
    validate_request,
)

ROOT = Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Fixtures" / "task"


class ExecuteBitProbeTests(unittest.TestCase):
    def test_has_execute_bit_reads_stat_bits_not_access(self):
        """Regression anchor (2026-10-03 hand test): App Sandbox denies
        access(X_OK) for staged paths while test -x passes in a shell, so
        presence probes must read POSIX bits from stat instead."""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            exe = root / "engine.sh"
            exe.write_text("#!/bin/sh\nexit 0\n")
            exe.chmod(0o755)
            self.assertTrue(has_execute_bit(exe))

            plain = root / "notes.txt"
            plain.write_text("plain text")
            plain.chmod(0o644)
            self.assertFalse(has_execute_bit(plain))

            # stat follows symlinks: the staged layout is
            # energyplus -> energyplus-25.2.0 inside the same directory.
            link = root / "energyplus"
            link.symlink_to(exe)
            self.assertTrue(has_execute_bit(link))

            self.assertFalse(has_execute_bit(root / "missing"))


class TaskProtocolTests(unittest.TestCase):
    def test_request_hash_matches_fixture_snapshot(self):
        request = json.loads((FIXTURES / "request-l1.json").read_text(encoding="utf-8"))
        snapshot = (FIXTURES / "snapshot.json").read_bytes()
        validate_request(request, snapshot)
        with self.assertRaises(TaskProtocolError) as raised:
            validate_request(request, b"not-the-snapshot")
        self.assertEqual(raised.exception.code, TaskProtocolError.hash_mismatch)

    def test_request_rejects_absolute_weather_path(self):
        request = json.loads((FIXTURES / "request-l1.json").read_text(encoding="utf-8"))
        request["weatherPath"] = "/Users/krabbypatty/weather.epw"
        with self.assertRaises(TaskProtocolError) as raised:
            validate_request(request, b"x")
        self.assertEqual(raised.exception.code, TaskProtocolError.unsafe_snapshot_path)

    def test_request_rejects_home_path(self):
        request = json.loads((FIXTURES / "request-l1.json").read_text(encoding="utf-8"))
        request["snapshotPath"] = "/Users/krabbypatty/office.json"
        with self.assertRaises(TaskProtocolError) as raised:
            validate_request(request, b"x")
        self.assertEqual(raised.exception.code, TaskProtocolError.unsafe_snapshot_path)

    def test_out_of_order_sequence_is_rejected(self):
        stream = EventStream("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        lines = (FIXTURES / "events-ok.jsonl").read_text(encoding="utf-8").splitlines()
        stream.ingest(lines[0] + "\n")
        with self.assertRaises(TaskProtocolError) as raised:
            stream.ingest(lines[0] + "\n")
        self.assertEqual(raised.exception.code, TaskProtocolError.stale_sequence)
        self.assertEqual(len(stream.events), 1)

    def test_truncated_line_and_wrong_run(self):
        stream = EventStream("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        first = (FIXTURES / "events-ok.jsonl").read_text(encoding="utf-8").splitlines()[0]
        self.assertEqual(stream.ingest(first[:20]), [])
        stream.ingest(first[20:] + "\n")
        self.assertEqual(len(stream.events), 1)
        hanging = EventStream("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        hanging.ingest('{"schemaVersion":1')
        with self.assertRaises(TaskProtocolError) as raised:
            hanging.finish()
        self.assertEqual(raised.exception.code, TaskProtocolError.truncated_line)
        foreign = first.replace("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        other = EventStream("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        with self.assertRaises(TaskProtocolError) as raised:
            other.ingest(foreign + "\n")
        self.assertEqual(raised.exception.code, TaskProtocolError.wrong_run)

    def test_result_omits_annual_energy(self):
        payload = json.loads((FIXTURES / "result-l1.json").read_text(encoding="utf-8"))
        result = parse_result(payload)
        cool = next(item for item in result["metrics"] if item["name"] == "q_cool_w")
        elec = next(item for item in result["metrics"] if item["name"] == "p_elec_w")
        annual = next(item for item in result["metrics"] if item["name"] == "annual_kwh")
        self.assertEqual(cool["value"], 6334.87)
        self.assertEqual(elec["value"], 2111.62)
        self.assertIsNone(annual["value"])
        self.assertTrue(annual["omitted"])
        self.assertEqual(result["period"]["kind"], "representative_day")
        self.assertEqual(result["weatherPath"], "weather/CHN_Hong.Kong.SAR.450070_CityUHK.epw")

    def test_l2_result_keeps_quality_detail_and_seat_samples(self):
        # The L2 fixture is a real pinned run: seats exist only because the
        # gates passed; parse_result must not drop that evidence.
        payload = json.loads((FIXTURES / "result-l2.json").read_text(encoding="utf-8"))
        result = parse_result(payload)
        self.assertEqual(result["quality"], "passed")
        self.assertEqual(result["qualityDetail"]["checkMesh"], "ok")
        self.assertTrue(result["qualityDetail"]["solverEnded"])
        # P4-07 re-pin follows the current office template (8 seats, comfort
        # defaults present), so the fixture carries 8 evaluated seats.
        self.assertEqual(len(result["seatSamples"]), 8)
        first = result["seatSamples"][0]
        self.assertEqual(first["id"], "S1")
        self.assertGreater(first["tC"], 15)
        self.assertIn("lowSpeedAbsoluteError", first)

    def test_l2_result_passes_omission_reasons_through(self):
        # Comfort metrics must keep their omission reason on the wire; the
        # value is never filled with a neutral 0 vote. The re-pinned office
        # fixture HAS comfort inputs, so the omission path is exercised by
        # stripping them from a copy of the payload, not by re-pinning a
        # comfort-less run (P5-01 keeps a separate comfort fixture).
        payload = json.loads((FIXTURES / "result-l2.json").read_text(encoding="utf-8"))
        reason = "not evaluable: missing mrtC, rhPct, clo, met (comfort inputs not modeled)"
        payload["metrics"] = [
            {"name": item["name"], "value": None, "unit": item.get("unit"), "method": "not_modeled", "fidelity": "l2", "omitted": True, "reason": reason}
            if item["name"].startswith("seat_pmv") or item["name"] == "seat_ppd_max"
            else item
            for item in payload["metrics"]
        ]
        payload["seatSamples"] = [
            {key: value for key, value in seat.items() if key not in ("pmv", "ppd")}
            for seat in payload["seatSamples"]
        ]
        result = parse_result(payload)
        pmv_min = next(item for item in result["metrics"] if item["name"] == "seat_pmv_min")
        self.assertTrue(pmv_min["omitted"])
        self.assertIsNone(pmv_min["value"])
        self.assertIn("missing", pmv_min["reason"])
        self.assertIn("mrtC", pmv_min["reason"])
        for row in result["seatSamples"]:
            self.assertNotIn("pmv", row)


if __name__ == "__main__":
    unittest.main()
