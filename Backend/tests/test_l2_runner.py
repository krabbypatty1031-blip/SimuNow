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
                seat_min = next(item for item in result["metrics"] if item["name"] == "seat_t_c_min")
                self.assertTrue(seat_min["omitted"])
                self.assertIsNone(seat_min["value"])
                self.assertEqual(result["state"], "failed")
                self.assertEqual(result["quality"], "notEvaluated")
                self.assertEqual(result["supplyTemperatureC"], 16)
                self.assertEqual(result["setpointC"], 26)
                self.assertTrue((run_dir / "case" / "system" / "blockMeshDict").is_file())
        finally:
            if previous is not None:
                os.environ["SIMUNOW_ENGINES_ROOT"] = previous

    def test_pinned_engines_run_l2_pipeline_with_quality(self):
        wrapper = ROOT / "test" / "engines" / "openfoam.sh"
        if not wrapper.is_file():
            self.skipTest("pinned OpenFOAM missing")
        previous = os.environ.get("SIMUNOW_ENGINES_ROOT")
        os.environ["SIMUNOW_ENGINES_ROOT"] = str(ROOT / "test" / "engines")
        try:
            with tempfile.TemporaryDirectory() as tmp:
                folder = Path(tmp)
                request, snapshot, run_dir = _write_job(folder, OFFICE)
                code = run_l2_task(["--request", str(request), "--snapshot", str(snapshot), "--run-dir", str(run_dir)])
                self.assertEqual(
                    code,
                    0,
                    (run_dir / "result.json").read_text(encoding="utf-8") if (run_dir / "result.json").is_file() else "no result",
                )
                result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
                self.assertEqual(result["state"], "succeeded")
                self.assertEqual(result["quality"], "passed")
                self.assertEqual(result["qualityDetail"]["checkMesh"], "ok")
                self.assertTrue(result["qualityDetail"]["monitorsStable"])
                self.assertTrue((run_dir / "quality.json").is_file())
                self.assertTrue((run_dir / "samples.json").is_file())
                seats = result["seatSamples"]
                self.assertEqual(len(seats), 4)
                for seat in seats:
                    self.assertGreater(seat["tC"], 15.0, "a seat colder than the 16C supply is not room air")
                    self.assertGreater(seat["uMag"], 0.0)
                seat_min = next(item for item in result["metrics"] if item["name"] == "seat_t_c_min")
                self.assertFalse(seat_min["omitted"])
                self.assertEqual(seat_min["value"], min(seat["tC"] for seat in seats))

                # Display-slice independence pin: seat values must equal the
                # nearest solve-mesh cell, re-derived from the case fields.
                import sys as _sys

                if str(ROOT / "test" / "p1") not in _sys.path:
                    _sys.path.insert(0, str(ROOT / "test" / "p1"))
                from foam_io import latest_time, parse_scalar_field, parse_vector_field
                from room_input import foam_xyz

                case = run_dir / "case"
                time_dir = latest_time(case)
                temps = parse_scalar_field((time_dir / "T").read_text(encoding="utf-8"))
                centres = parse_vector_field((time_dir / "C").read_text(encoding="utf-8"))
                samples = json.loads((run_dir / "samples.json").read_text(encoding="utf-8"))
                for row in samples["seats"]:
                    fx, fy, fz = foam_xyz(float(row["x"]), float(row["y"]), float(row["z"]))
                    index = min(
                        range(len(centres)),
                        key=lambda i: (centres[i][0] - fx) ** 2 + (centres[i][1] - fy) ** 2 + (centres[i][2] - fz) ** 2,
                    )
                    self.assertAlmostEqual(row["T_C"], temps[index] - 273.15, places=9)
        finally:
            if previous is None:
                os.environ.pop("SIMUNOW_ENGINES_ROOT", None)
            else:
                os.environ["SIMUNOW_ENGINES_ROOT"] = previous


if __name__ == "__main__":
    unittest.main()
