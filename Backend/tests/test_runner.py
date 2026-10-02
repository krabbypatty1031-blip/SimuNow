"""Runner/events tests: protocol validation, hash identity, cancellation, evidence retention.

Uses the artificial contract fixture; these tests verify run plumbing, not physics.
"""
import io
import json
import re
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch
from uuid import uuid4

import fixture_factory
from simunow_worker.__main__ import main as cli_main
from simunow_worker.jobs import runner
from simunow_worker.jobs.events import EventStream
from simunow_worker.adapters.l0 import steady_state
from simunow_worker.models.codec import ProjectCodec, ScenarioSnapshotBuilder
from simunow_worker.models.hashing import snapshot_hash
from simunow_worker.models.registry import native


def make_input(change=None, **overrides):
    project = ProjectCodec().decode(json.dumps(fixture_factory.project()))
    snapshot = ScenarioSnapshotBuilder.capture(project, project.scenarios[0].id)
    if change:
        snapshot = change(snapshot)
    envelope = {"protocol": "run-input/1", "runID": str(uuid4()).upper(),
                "scenarioID": str(snapshot.scenario_id).upper(),
                "inputHash": snapshot_hash(snapshot), "fidelity": "l0",
                "snapshot": json.loads(ProjectCodec().encode_snapshot(snapshot))}
    envelope.update(overrides)
    return envelope


def read_events(path):
    text = path.read_text(encoding="utf-8")
    return [json.loads(line) for line in text.splitlines()]


class EventStreamTests(unittest.TestCase):
    def test_stdout_is_pure_jsonl_and_tee_matches(self):
        with TemporaryDirectory() as tmp:
            tee = Path(tmp) / "events.jsonl"
            out = io.StringIO()
            with patch("sys.stdout", out):
                with EventStream("RUN-ID", tee_path=tee) as events:
                    events.emit("accepted", payload={"fidelity": "l0"})
                    events.emit("progress", stage="solving", payload={"step": 1, "totalSteps": 2})
                    events.emit("completed", payload={"state": "completed"})
            lines = out.getvalue().splitlines()
            self.assertEqual(len(lines), 3)
            for i, line in enumerate(lines, start=1):
                event = json.loads(line)
                self.assertEqual(event["protocol"], "run-event/1")
                self.assertEqual(event["runID"], "RUN-ID")
                self.assertEqual(event["sequence"], i)
                self.assertRegex(event["timestamp"], r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$")
            self.assertEqual(tee.read_text(encoding="utf-8"), out.getvalue())

    def test_unknown_event_type_rejected(self):
        with patch("sys.stdout", io.StringIO()):
            with EventStream("RUN-ID") as events:
                with self.assertRaises(ValueError):
                    events.emit("half_done")


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.input_path = self.root / "input.json"
        self.run_dir = self.root / "run"

    def tearDown(self):
        self.tmp.cleanup()

    def write_input(self, envelope):
        self.input_path.write_text(json.dumps(envelope), encoding="utf-8")

    def execute(self, envelope, cancel_file=None):
        self.write_input(envelope)
        out = io.StringIO()
        with patch("sys.stdout", out):
            code = runner.run_job(self.input_path, self.run_dir, cancel_file)
        return code, out.getvalue()

    def test_completed_run_writes_events_and_atomic_result(self):
        envelope = make_input()
        code, stdout = self.execute(envelope)
        self.assertEqual(code, 0)
        events = read_events(self.run_dir / "events.jsonl")
        self.assertEqual(events[0]["eventType"], "accepted")
        self.assertEqual(events[-1]["eventType"], "completed")
        self.assertEqual([e["sequence"] for e in events], list(range(1, len(events) + 1)))
        self.assertTrue(all(e["runID"] == envelope["runID"] for e in events))
        self.assertEqual(stdout, (self.run_dir / "events.jsonl").read_text(encoding="utf-8"))
        result = json.loads((self.run_dir / "result.json").read_text(encoding="utf-8"))
        self.assertEqual(result["protocol"], "run-result/1")
        self.assertEqual(result["state"], "completed")
        self.assertEqual(result["identity"]["runID"], envelope["runID"])
        self.assertEqual(result["identity"]["inputHash"], envelope["inputHash"])
        self.assertEqual(result["quality"]["state"], "passed")
        names = {m["name"] for m in result["metrics"]}
        self.assertIn("dailyCoolingEnergy", names)
        self.assertTrue(result["assumptions"])
        self.assertFalse(list(self.run_dir.glob("*.tmp")))

    def test_missing_values_are_null_with_reason_not_zero(self):
        def hide_setpoint(snapshot):
            data = json.loads(ProjectCodec().encode_snapshot(snapshot))
            data["inputs"]["controls"][0]["setpoint"] = fixture_factory.unknown("No thermostat reading")
            return ProjectCodec().decode_snapshot(json.dumps(data))
        code, _ = self.execute(make_input(change=hide_setpoint))
        self.assertEqual(code, 0)
        result = json.loads((self.run_dir / "result.json").read_text(encoding="utf-8"))
        by_name = {m["name"]: m for m in result["metrics"]}
        self.assertIsNone(by_name["coolingLoadPeak"]["value"])
        self.assertIn("missing_reason", by_name["coolingLoadPeak"])

    def test_hash_mismatch_fails_with_exit_3(self):
        envelope = make_input(inputHash="0" * 64)
        code, _ = self.execute(envelope)
        self.assertEqual(code, 3)
        events = read_events(self.run_dir / "events.jsonl")
        self.assertEqual(events[-1]["eventType"], "failed")
        result = json.loads((self.run_dir / "result.json").read_text(encoding="utf-8"))
        self.assertEqual(result["state"], "failed")
        self.assertEqual(result["error"]["kind"], "input_hash_mismatch")

    def test_invalid_envelope_produces_no_events(self):
        for label, mutate in {
            "wrong_protocol": lambda e: e.update(protocol="run-input/0"),
            "unconfigured_fidelity": lambda e: e.update(fidelity="l1"),
            "bad_run_id": lambda e: e.update(runID="not-a-uuid"),
            "bad_hash_shape": lambda e: e.update(inputHash="xyz"),
            "scenario_mismatch": lambda e: e.update(scenarioID=str(uuid4()).upper()),
        }.items():
            with self.subTest(label=label):
                envelope = make_input()
                mutate(envelope)
                self.write_input(envelope)
                err = io.StringIO()
                with patch("sys.stderr", err):
                    code = runner.main(["--input", str(self.input_path), "--run-dir", str(self.run_dir)])
                self.assertEqual(code, 3)
                self.assertIn("invalid run input", err.getvalue())
                self.assertFalse((self.run_dir / "events.jsonl").exists())

    def test_invalid_snapshot_fails_with_evidence(self):
        envelope = make_input()
        envelope["snapshot"]["inputs"]["controls"][0]["setpoint"] = {"state": "known", "value": "warm"}
        self.write_input(envelope)
        with patch("sys.stdout", io.StringIO()):
            code = runner.run_job(self.input_path, self.run_dir)
        self.assertEqual(code, 1)
        result = json.loads((self.run_dir / "result.json").read_text(encoding="utf-8"))
        self.assertEqual(result["error"]["kind"], "invalid_snapshot")

    def test_cancel_before_start_is_clean_terminal_state(self):
        cancel = self.root / "cancel-requested"
        cancel.touch()
        code, _ = self.execute(make_input(), cancel_file=cancel)
        self.assertEqual(code, 0)
        events = read_events(self.run_dir / "events.jsonl")
        self.assertEqual([e["eventType"] for e in events], ["accepted", "cancelled"])
        result = json.loads((self.run_dir / "result.json").read_text(encoding="utf-8"))
        self.assertEqual(result["state"], "cancelled")

    def test_repeated_cancel_is_harmless(self):
        cancel = self.root / "cancel-requested"
        for _ in range(2):
            run_dir = self.root / f"run-{uuid4()}"
            cancel.touch()  # cancelling again must never error
            self.write_input(make_input())
            with patch("sys.stdout", io.StringIO()):
                code = runner.run_job(self.input_path, run_dir, cancel)
            self.assertEqual(code, 0)
            result = json.loads((run_dir / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(result["state"], "cancelled")

    def test_cancel_during_computation(self):
        cancel = self.root / "cancel-requested"
        real_run = steady_state.run

        def cancelling_run(snapshot, registry=None, should_cancel=None):
            def trigger():
                cancel.touch()
                return should_cancel()
            return real_run(snapshot, registry=registry, should_cancel=trigger)

        with patch.object(steady_state, "run", cancelling_run):
            code, _ = self.execute(make_input(), cancel_file=cancel)
        self.assertEqual(code, 0)
        events = read_events(self.run_dir / "events.jsonl")
        self.assertEqual(events[-1]["eventType"], "cancelled")

    def test_adapter_error_keeps_evidence(self):
        def broken(snapshot, registry=None, should_cancel=None):
            raise RuntimeError("synthetic adapter failure")

        with patch.object(steady_state, "run", broken):
            code, _ = self.execute(make_input())
        self.assertEqual(code, 1)
        events = read_events(self.run_dir / "events.jsonl")
        self.assertEqual(events[-1]["eventType"], "failed")
        result = json.loads((self.run_dir / "result.json").read_text(encoding="utf-8"))
        self.assertEqual(result["error"]["kind"], "adapter_error")
        self.assertIn("synthetic adapter failure", (self.run_dir / "stderr.log").read_text(encoding="utf-8"))

    def test_cli_run_entrypoint(self):
        envelope = make_input()
        self.write_input(envelope)
        with patch("sys.stdout", io.StringIO()):
            code = cli_main(["run", "--input", str(self.input_path), "--run-dir", str(self.run_dir)])
        self.assertEqual(code, 0)
        self.assertTrue((self.run_dir / "result.json").exists())

    def test_cli_run_requires_paths(self):
        with patch("sys.stderr", io.StringIO()), self.assertRaises(SystemExit) as ctx:
            cli_main(["run"])
        self.assertEqual(ctx.exception.code, 2)


class CliSubprocessTests(unittest.TestCase):
    def test_module_run_end_to_end(self):
        import subprocess
        import sys
        with TemporaryDirectory() as tmp:
            root = Path(tmp)
            envelope = make_input()
            (root / "input.json").write_text(json.dumps(envelope), encoding="utf-8")
            proc = subprocess.run(
                [sys.executable, "-m", "simunow_worker", "run",
                 "--input", str(root / "input.json"), "--run-dir", str(root / "run")],
                capture_output=True, text=True, timeout=30)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            lines = proc.stdout.splitlines()
            self.assertTrue(lines)
            for line in lines:
                self.assertEqual(json.loads(line)["protocol"], "run-event/1")
            result = json.loads((root / "run" / "result.json").read_text(encoding="utf-8"))
            self.assertEqual(result["state"], "completed")
            self.assertTrue(re.fullmatch(r"[0-9a-f]{64}", result["identity"]["inputHash"]))


if __name__ == "__main__":
    unittest.main()
