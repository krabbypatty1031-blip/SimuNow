"""run-l2 must not invent seat temperatures when OpenFOAM is missing."""

from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

from simunow_worker.l2_runner import run_l2_task
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
        "fidelity": "l2",
        "snapshotPath": "runs/input.json",
        "snapshotHash": digest,
    }
    request_path = folder / "request.json"
    request_path.write_text(json.dumps(request), encoding="utf-8")
    run_dir = folder / "run"
    run_dir.mkdir()
    return request_path, snapshot, run_dir


class L2RunnerTests(unittest.TestCase):
    def test_missing_engine_fails_without_invented_seat_temperature(self):
        previous = os.environ.pop("SIMUNOW_ENGINES_ROOT", None)
        try:
            with tempfile.TemporaryDirectory() as tmp:
                folder = Path(tmp)
                request, snapshot, run_dir = _write_job(folder, OFFICE)
                code = run_l2_task(["--request", str(request), "--snapshot", str(snapshot), "--run-dir", str(run_dir)])
                self.assertEqual(code, 1)
                result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
                seat = next(item for item in result["metrics"] if item["name"] == "seat_t_c")
                self.assertTrue(seat["omitted"])
                self.assertIsNone(seat["value"])
                self.assertEqual(result["state"], "failed")
                self.assertEqual(result["supplyTemperatureC"], 16)
                self.assertEqual(result["setpointC"], 26)
                self.assertTrue((run_dir / "case" / "system" / "blockMeshDict").is_file())
        finally:
            if previous is not None:
                os.environ["SIMUNOW_ENGINES_ROOT"] = previous


if __name__ == "__main__":
    unittest.main()
