"""Run the real worker end-to-end and validate its artifacts against the P3 schemas.

Two artificial fixture projects (office/classroom) are turned into RunInput files,
executed through the real CLI (`python -m simunow_worker run`), and every emitted
event line plus the atomic result.json is validated with an independent
Draft202012Validator. Snapshot deep-validation is referenced from run-input to
scenario-input-snapshot.schema.json via a retrieving registry.
"""
import json
import subprocess
import sys
from pathlib import Path
from tempfile import TemporaryDirectory
from uuid import uuid4

from fixture_factory import project
from schema_registry import make_registry, validator
from simunow_worker.models.codec import ProjectCodec, ScenarioSnapshotBuilder
from simunow_worker.models.hashing import snapshot_hash


def main():
    registry = make_registry()
    v_input = validator("run-input.schema.json", registry)
    v_event = validator("run-event.schema.json", registry)
    v_result = validator("run-result.schema.json", registry)
    codec = ProjectCodec()
    with TemporaryDirectory() as tmp:
        root = Path(tmp)
        for space in ("office", "classroom"):
            project_doc = codec.decode(json.dumps(project(space)))
            snapshot = ScenarioSnapshotBuilder.capture(project_doc, project_doc.scenarios[0].id)
            run_id = str(uuid4()).upper()
            envelope = {"protocol": "run-input/1", "runID": run_id,
                        "scenarioID": str(snapshot.scenario_id).upper(),
                        "inputHash": snapshot_hash(snapshot), "fidelity": "l0",
                        "snapshot": json.loads(codec.encode_snapshot(snapshot))}
            input_path = root / f"{space}.input.json"
            input_path.write_text(json.dumps(envelope), encoding="utf-8")
            v_input.validate(json.loads(input_path.read_text(encoding="utf-8")))
            run_dir = root / f"{space}.run"
            proc = subprocess.run(
                [sys.executable, "-m", "simunow_worker", "run",
                 "--input", str(input_path), "--run-dir", str(run_dir)],
                capture_output=True, text=True, timeout=60)
            if proc.returncode != 0:
                raise SystemExit(f"worker run failed for {space}: {proc.stderr}")
            lines = proc.stdout.splitlines()
            if not lines:
                raise SystemExit(f"worker emitted no events for {space}")
            for line in lines:
                v_event.validate(json.loads(line))
            if [json.loads(line)["sequence"] for line in lines] != list(range(1, len(lines) + 1)):
                raise SystemExit(f"event sequence is not contiguous for {space}")
            if (run_dir / "events.jsonl").read_text(encoding="utf-8") != proc.stdout:
                raise SystemExit(f"events.jsonl differs from stdout for {space}")
            if json.loads(lines[0])["eventType"] != "accepted" or json.loads(lines[-1])["eventType"] != "completed":
                raise SystemExit(f"unexpected terminal events for {space}")
            result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
            v_result.validate(result)
            if result["identity"]["inputHash"] != envelope["inputHash"] or result["identity"]["runID"] != run_id:
                raise SystemExit(f"result identity mismatch for {space}")
    print("Contract run passed: 2 real L0 runs validated against run-input/run-event/run-result schemas.")


if __name__ == "__main__":
    main()
