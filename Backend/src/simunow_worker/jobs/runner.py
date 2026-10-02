"""Run command: execute one fidelity job from a RunInput file (Protocols/run-input-v1.md).

- Validates protocol, fidelity, identity fields and input hash before any computation.
- Emits the run-events-v1 JSONL stream on stdout (teed to events.jsonl).
- Writes result.json atomically (tmp file + rename); a run only ever writes
  inside its own run directory.
- Cancellation is a marker file polled between steps; repeated cancels are
  harmless and a cancel requested before the start still yields a cancelled
  result, never a crash.
Exit codes: 0 completed or cancelled; 1 the run failed (evidence kept);
3 the run input itself is invalid (protocol/hash/fidelity/identity).
"""
import json
import os
import re
import sys
import tempfile
import traceback
from datetime import datetime, timezone
from pathlib import Path
from uuid import UUID

from ..models.codec import ProjectCodec
from ..models.hashing import snapshot_hash
from ..models.json_value import parse, render
from ..models.registry import default_registry
from .events import EventStream

RESULT_PROTOCOL = "run-result/1"
INPUT_PROTOCOL = "run-input/1"


def _now():
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class InvalidInput(Exception):
    pass


def _atomic_write(path: Path, text: str):
    handle, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".result-", suffix=".tmp")
    try:
        with os.fdopen(handle, "w", encoding="utf-8") as out:
            out.write(text)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _uuid(value):
    try:
        return str(UUID(str(value))).upper()
    except (ValueError, AttributeError, TypeError):
        raise InvalidInput(f"not a UUID: {value!r}")


def _parse_input(path: Path):
    try:
        raw = parse(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise InvalidInput(f"unreadable run input: {error}")
    if not isinstance(raw, dict) or raw.get("protocol") != INPUT_PROTOCOL:
        raise InvalidInput(f"protocol must be {INPUT_PROTOCOL}")
    for key in ("runID", "scenarioID", "inputHash", "fidelity", "snapshot"):
        if key not in raw:
            raise InvalidInput(f"missing field: {key}")
    if raw["fidelity"] != "l0":
        raise InvalidInput(f"fidelity {raw['fidelity']} is not configured in this worker")
    raw["runID"] = _uuid(raw["runID"])
    raw["scenarioID"] = _uuid(raw["scenarioID"])
    if not isinstance(raw["inputHash"], str) or not re.fullmatch(r"[0-9a-fA-F]{64}", raw["inputHash"]):
        raise InvalidInput("inputHash must be 64 hex characters")
    snapshot = raw["snapshot"]
    if not isinstance(snapshot, dict):
        raise InvalidInput("snapshot must be an object")
    snapshot_scenario = snapshot.get("scenarioID")
    if not isinstance(snapshot_scenario, str) or snapshot_scenario.upper() != raw["scenarioID"]:
        raise InvalidInput("scenarioID does not match snapshot.scenarioID")
    return raw


def run_job(input_path: Path, run_dir: Path, cancel_file: Path = None):
    run_dir.mkdir(parents=True, exist_ok=True)
    events_path = run_dir / "events.jsonl"
    raw = _parse_input(input_path)  # raises InvalidInput before any event is emitted
    run_id, scenario_id, expected_hash = str(raw["runID"]), str(raw["scenarioID"]), raw["inputHash"]

    with EventStream(run_id, tee_path=events_path) as events:
        started = _now()
        result = {"protocol": RESULT_PROTOCOL,
                  "identity": {"runID": run_id, "scenarioID": scenario_id, "inputHash": expected_hash},
                  "fidelity": raw["fidelity"], "state": None,
                  "metrics": [], "quality": {"state": "notEvaluated", "checks": []},
                  "assumptions": [], "startedAt": started, "finishedAt": None}

        def finish(state, error=None):
            result["state"] = state
            result["finishedAt"] = _now()
            if error is not None:
                result["error"] = error
            _atomic_write(run_dir / "result.json", json.dumps(result, ensure_ascii=False, indent=1))
            events.emit(state if state in ("completed", "failed", "cancelled") else "failed",
                        payload={"state": state})

        def cancelled():
            return cancel_file is not None and cancel_file.exists()

        events.emit("accepted", payload={"fidelity": raw["fidelity"], "scenarioID": scenario_id})
        try:
            # Decode through the same strict wire boundary as project I/O: alias handling,
            # tuple conversion and known-payload validation included.
            snapshot = ProjectCodec().decode_snapshot(render(raw["snapshot"]))
        except ValueError as error:
            finish("failed", {"kind": "invalid_snapshot", "message": str(error)[:2000]})
            return 1
        actual_hash = snapshot_hash(snapshot)
        if not isinstance(expected_hash, str) or actual_hash != expected_hash.lower():
            events.emit("log", payload={"level": "error", "message": "input hash mismatch",
                                        "expected": expected_hash, "actual": actual_hash})
            finish("failed", {"kind": "input_hash_mismatch",
                              "message": "inputHash does not match the snapshot; the request is stale or corrupt"})
            return 3
        if cancelled():
            finish("cancelled")
            return 0

        from ..adapters.l0 import steady_state

        steps = {"total": 48}
        progress = {"done": 0}

        def should_cancel():
            progress["done"] += 1
            if progress["done"] % 8 == 0 or progress["done"] == steps["total"]:
                events.emit("progress", stage="solving",
                            payload={"step": progress["done"], "totalSteps": steps["total"]})
            return cancelled()

        try:
            outcome = steady_state.run(snapshot, registry=default_registry(), should_cancel=should_cancel)
        except steady_state.Cancelled:
            finish("cancelled")
            return 0
        except Exception as error:  # adapter defect: keep evidence, never silently succeed
            events.emit("log", payload={"level": "error", "message": str(error)[:2000]})
            (run_dir / "stderr.log").write_text(traceback.format_exc(), encoding="utf-8")
            finish("failed", {"kind": "adapter_error", "message": str(error)[:2000]})
            return 1

        result["metrics"] = outcome["metrics"]
        result["quality"] = outcome["quality"]
        result["assumptions"] = outcome["assumptions"]
        events.emit("quality", stage="checking", payload=outcome["quality"])
        finish("completed")
        return 0


def main(argv=None):
    import argparse
    parser = argparse.ArgumentParser(prog="simunow-worker run")
    parser.add_argument("--input", type=Path, required=True, help="RunInput JSON file (run-input/1)")
    parser.add_argument("--run-dir", type=Path, required=True, help="Directory for events.jsonl and result.json")
    parser.add_argument("--cancel-file", type=Path, default=None, help="Marker file polled for cancellation")
    args = parser.parse_args(argv)
    try:
        return run_job(args.input, args.run_dir, args.cancel_file)
    except InvalidInput as error:
        # No events may reference an unknown run id; report on stderr and exit 3.
        sys.stderr.write(f"invalid run input: {error}\n")
        return 3
