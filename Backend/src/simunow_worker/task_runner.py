"""Emit P3 JSONL events. This stub does not run EnergyPlus or invent watt-hours."""

from __future__ import annotations

import argparse
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

from .models.task import validate_request


def _event(request: dict, sequence: int, event_type: str, stage: str, payload: dict | None = None) -> dict:
    identity = request["identity"]
    return {
        "schemaVersion": 1,
        "runID": identity["runID"],
        "scenarioID": identity["scenarioID"],
        "inputHash": identity["inputHash"],
        "sequence": sequence,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "eventType": event_type,
        "stage": stage,
        "payload": payload or {},
    }


def _emit(event: dict) -> None:
    sys.stdout.write(json.dumps(event, separators=(",", ":"), ensure_ascii=False) + "\n")
    sys.stdout.flush()


def run_stub(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="simunow-worker stub-task")
    parser.add_argument("--request", required=True)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--sleep", type=float, default=0)
    parser.add_argument("--fail", action="store_true")
    args = parser.parse_args(argv)

    request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    snapshot = Path(args.snapshot).read_bytes()
    validate_request(request, snapshot)

    # Never print the operator home directory; keep diagnostics relative.
    sys.stderr.write("stub-task start run-dir=runs/%s\n" % Path(args.run_dir).name)
    sys.stderr.flush()

    _emit(_event(request, 0, "accepted", "queued", {"message": "accepted"}))
    if args.sleep > 0:
        time.sleep(args.sleep)
    if args.fail:
        _emit(_event(request, 1, "failed", "failed", {"message": "stub failed without solver"}))
        sys.stderr.write("stub-task failed without calling EnergyPlus\n")
        return 1
    _emit(_event(request, 1, "progress", "solving", {"fraction": 1.0, "monitor": "stub"}))
    _emit(_event(request, 2, "completed", "succeeded", {"message": "stub completed"}))
    return 0
