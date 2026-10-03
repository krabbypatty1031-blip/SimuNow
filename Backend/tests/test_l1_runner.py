import json
import os
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

from simunow_worker.l1_runner import run_l1_task
from simunow_worker.models.task import sha256_hex

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]


def _write_job(folder: Path, draft: dict) -> tuple[Path, Path, Path]:
    snapshot = folder / "input.json"
    snapshot.write_text(json.dumps(draft, ensure_ascii=False), encoding="utf-8")
    digest = sha256_hex(snapshot.read_bytes())
    request = {
        "schemaVersion": 1,
        "identity": {
            "runID": str(uuid4()),
            "scenarioID": str(uuid4()),
            "inputHash": digest,
        },
        "fidelity": "l1",
        "snapshotPath": "runs/input.json",
        "snapshotHash": digest,
    }
    request_path = folder / "request.json"
    request_path.write_text(json.dumps(request), encoding="utf-8")
    run_dir = folder / "run"
    run_dir.mkdir()
    return request_path, snapshot, run_dir


class L1RunnerTests(unittest.TestCase):
    def test_missing_engine_fails_without_invented_watts(self):
        previous = os.environ.pop("SIMUNOW_ENGINES_ROOT", None)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                folder = Path(tmp)
                request, snapshot, run_dir = _write_job(folder, OFFICE)
                code = run_l1_task(["--request", str(request), "--snapshot", str(snapshot), "--run-dir", str(run_dir)])
                self.assertEqual(code, 1)
                result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
                cool = next(item for item in result["metrics"] if item["name"] == "q_cool_w")
                self.assertTrue(cool["omitted"])
                self.assertIsNone(cool["value"])
                self.assertEqual(result["state"], "failed")
        finally:
            if previous is not None:
                os.environ["SIMUNOW_ENGINES_ROOT"] = previous

    def test_pinned_engines_write_cooling_and_electricity(self):
        binary = ROOT / "test" / "engines" / "EnergyPlus" / "energyplus"
        if not binary.is_file():
            self.skipTest("pinned EnergyPlus missing")
        previous = os.environ.get("SIMUNOW_ENGINES_ROOT")
        os.environ["SIMUNOW_ENGINES_ROOT"] = str(ROOT / "test" / "engines")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                folder = Path(tmp)
                request, snapshot, run_dir = _write_job(folder, OFFICE)
                code = run_l1_task(["--request", str(request), "--snapshot", str(snapshot), "--run-dir", str(run_dir)])
                result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
                self.assertEqual(code, 0, result)
                cool = next(item for item in result["metrics"] if item["name"] == "q_cool_w")
                elec = next(item for item in result["metrics"] if item["name"] == "p_elec_w")
                annual = next(item for item in result["metrics"] if item["name"] == "annual_kwh")
                self.assertFalse(cool["omitted"])
                self.assertGreater(cool["value"], 0)
                self.assertAlmostEqual(elec["value"], cool["value"] / 3.0)
                self.assertTrue(annual["omitted"])
                self.assertEqual(result["supplyTemperatureC"], 16)
                self.assertEqual(result["setpointC"], 26)
        finally:
            if previous is None:
                os.environ.pop("SIMUNOW_ENGINES_ROOT", None)
            else:
                os.environ["SIMUNOW_ENGINES_ROOT"] = previous


if __name__ == "__main__":
    unittest.main()
