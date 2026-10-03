"""In-app L2 must run from the staged worker tree the App copies.

The App stages Backend/src/simunow_worker plus nine test/p1 helpers plus
test/engines/openfoam.sh into its container runtime. This test rebuilds that
layout and runs `python -m simunow_worker run-l2` as a subprocess, the same
way LocalProcessL2Client does, so a missing staged script or a mismatched
engine path fails here instead of inside the App.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[2]
OFFICE = json.loads((ROOT / "Fixtures" / "templates" / "office.json").read_text(encoding="utf-8"))["project"]

# Keep this list in sync with WorkerTreeStaging.stageWorker in the Swift package.
P1_SCRIPTS = [
    "write_idf.py",
    "run_l1.py",
    "room_input.py",
    "run_room.py",
    "write_openfoam_room.py",
    "quality.py",
    "sample_seats.py",
    "foam_io.py",
    "field_slice.py",
]


def _stage_worker_tree(dest: Path) -> Path:
    """Mirror WorkerTreeStaging: worker package, P1 helpers, engine wrapper."""
    worker_dest = dest / "Backend" / "src" / "simunow_worker"
    shutil.copytree(ROOT / "Backend" / "src" / "simunow_worker", worker_dest)
    p1_dest = dest / "test" / "p1"
    p1_dest.mkdir(parents=True)
    for name in P1_SCRIPTS:
        shutil.copy2(ROOT / "test" / "p1" / name, p1_dest / name)
    engines_dest = dest / "test" / "engines"
    engines_dest.mkdir(parents=True)
    shutil.copy2(ROOT / "test" / "engines" / "openfoam.sh", engines_dest / "openfoam.sh")
    return dest


class StagedL2Tests(unittest.TestCase):
    def test_staged_tree_runs_l2_and_writes_slice(self):
        source_wrapper = ROOT / "test" / "engines" / "openfoam.sh"
        if not source_wrapper.is_file():
            self.skipTest("pinned OpenFOAM missing")
        with tempfile.TemporaryDirectory() as tmp:
            staged = _stage_worker_tree(Path(tmp))
            run_dir = staged / "runs" / "run"
            run_dir.mkdir(parents=True)
            snapshot = run_dir.parent / "input.json"
            snapshot.write_text(json.dumps(OFFICE, ensure_ascii=False), encoding="utf-8")
            from simunow_worker.models.task import sha256_hex

            digest = sha256_hex(snapshot.read_bytes())
            request = {
                "schemaVersion": 1,
                "identity": {"runID": str(uuid4()), "scenarioID": str(uuid4()), "inputHash": digest},
                "fidelity": "l2",
                "snapshotPath": "runs/input.json",
                "snapshotHash": digest,
            }
            request_path = run_dir.parent / "request.json"
            request_path.write_text(json.dumps(request), encoding="utf-8")

            env = dict(os.environ)
            env["PYTHONPATH"] = str(staged / "Backend" / "src")
            env["SIMUNOW_ENGINES_ROOT"] = str(staged / "test" / "engines")
            completed = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "simunow_worker",
                    "run-l2",
                    "--request",
                    str(request_path),
                    "--snapshot",
                    str(snapshot),
                    "--run-dir",
                    str(run_dir),
                ],
                cwd=str(staged),
                env=env,
                capture_output=True,
                text=True,
                timeout=900,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr + completed.stdout)
            result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(result["state"], "succeeded")
            self.assertEqual(result["quality"], "passed")
            # Quality-passed runs must expose the seat-height field slice at the
            # exact path the App reads (runDir/field-slice.json).
            slice_path = run_dir / "field-slice.json"
            self.assertTrue(slice_path.is_file())
            payload = json.loads(slice_path.read_text(encoding="utf-8"))
            self.assertEqual(payload["quality"], "passed")
            self.assertEqual(payload["axisOrder"], ["y", "x"])
            self.assertGreater(payload["stats"]["validCount"], 0)


if __name__ == "__main__":
    unittest.main()
