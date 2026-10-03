"""Run an L2 OpenFOAM steady case from a P2 snapshot.

Writes the case first so a missing engine still leaves evidence, then runs the
P1 pipeline (mesh, solve, checks, sampling). Seat temperatures come only from
a quality-passed field; nothing is invented when the engine is missing.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from .models.comfort import comfort_inputs_from_draft
from .models.l2_accounting import evaluate_l2, quality_detail
from .models.l2_room import project_to_l2_room
from .models.task import has_execute_bit, validate_request
from .task_runner import _emit, _event


def _repo_root() -> Path:
    cwd = Path.cwd()
    if (cwd / "test" / "p1" / "write_openfoam_room.py").is_file():
        return cwd
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "test" / "p1" / "write_openfoam_room.py").is_file():
            return parent
    return cwd


def _import_p1():
    p1 = _repo_root() / "test" / "p1"
    if str(p1) not in sys.path:
        sys.path.insert(0, str(p1))
    import run_room
    import write_openfoam_room as writer
    from room_input import RoomError

    return run_room, writer, RoomError


def _engines_root() -> Path | None:
    raw = os.environ.get("SIMUNOW_ENGINES_ROOT", "").strip()
    if not raw:
        return None
    root = Path(raw)
    return root if root.is_dir() else None


def _openfoam_wrapper(root: Path) -> Path | None:
    script = root / "openfoam.sh"
    # Execute bits via stat: os.access X_OK is denied in the App sandbox for
    # staged paths (2026-10-03 hand test); the run stays the engine's evidence.
    if has_execute_bit(script):
        return script
    return None


def _write_result(run_dir: Path, result: dict) -> None:
    (run_dir / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _seat_rows(run_dir: Path) -> list[dict] | None:
    """Map P1 samples.json onto the contract seat rows (Z-up, °C, m/s)."""
    path = run_dir / "samples.json"
    if not path.is_file():
        return None
    try:
        samples = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    rows = []
    for seat in samples.get("seats", []):
        row = {
            "id": str(seat["id"]),
            "x": float(seat["x"]),
            "y": float(seat["y"]),
            "z": float(seat["z"]),
            "tC": float(seat["T_C"]),
            "uMag": float(seat["U_mag"]),
        }
        if seat.get("abs_error_m_s"):
            row["lowSpeedAbsoluteError"] = True
        rows.append(row)
    return rows or None


def _quality_json(run_dir: Path) -> dict | None:
    path = run_dir / "quality.json"
    if not path.is_file():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None


def run_l2_task(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="simunow-worker run-l2")
    parser.add_argument("--request", required=True)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args(argv)

    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    snapshot = Path(args.snapshot).read_bytes()
    validate_request(request, snapshot)
    draft = json.loads(snapshot.decode("utf-8"))

    sys.stderr.write("run-l2 start run-dir=runs/%s\n" % run_dir.name)
    sys.stderr.flush()
    _emit(_event(request, 0, "accepted", "queued", {"message": "accepted"}))

    identity = request["identity"]
    try:
        room = project_to_l2_room(draft)
    except (ValueError, KeyError, TypeError) as exc:
        _emit(_event(request, 1, "failed", "failed", {"message": f"incomplete project: {exc}"}))
        return 1

    (run_dir / "l2-room.json").write_text(json.dumps(room, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    run_room, writer, room_error = _import_p1()
    writer.write_openfoam_room(room, run_dir / "case")
    _emit(_event(request, 1, "progress", "meshing", {"fraction": 0.15, "monitor": "blockMeshDict"}))

    engines = _engines_root()
    wrapper = _openfoam_wrapper(engines) if engines else None
    if wrapper is None:
        result = evaluate_l2(
            identity,
            draft,
            {
                "qualityDetail": None,
                "seatSamples": None,
                "pipelineCompleted": False,
                "comfortInputs": comfort_inputs_from_draft(draft),
            },
        )
        _write_result(run_dir, result)
        _emit(_event(request, 2, "failed", "failed", {"message": "OpenFOAM not configured"}))
        sys.stderr.write("run-l2 failed: OpenFOAM not configured; no invented seat temperature\n")
        return 1

    _emit(_event(request, 2, "progress", "solving", {"fraction": 0.35, "monitor": "buoyantBoussinesqSimpleFoam"}))
    try:
        run_room.run_pipeline(room, run_dir, timeout=600)
    except (room_error, subprocess.TimeoutExpired, OSError, KeyError, ValueError) as exc:
        # The case and logs stay in the run directory as failure evidence.
        result = evaluate_l2(
            identity,
            draft,
            {
                "qualityDetail": quality_detail(_quality_json(run_dir)),
                "seatSamples": None,
                "pipelineCompleted": False,
                "comfortInputs": comfort_inputs_from_draft(draft),
            },
        )
        _write_result(run_dir, result)
        _emit(_event(request, 3, "failed", "failed", {"message": f"l2 pipeline failed: {exc}"}))
        sys.stderr.write("run-l2 failed: %s\n" % exc)
        return 1

    _emit(_event(request, 3, "progress", "checking", {"fraction": 0.9, "monitor": "quality"}))
    result = evaluate_l2(
        identity,
        draft,
        {
            "qualityDetail": quality_detail(_quality_json(run_dir)),
            "seatSamples": _seat_rows(run_dir),
            "pipelineCompleted": True,
            "comfortInputs": comfort_inputs_from_draft(draft),
        },
    )
    _write_result(run_dir, result)
    detail = result.get("qualityDetail")
    if result["quality"] == "passed":
        _emit(_event(request, 4, "quality", "checking", {"message": "quality passed"}))
        _emit(_event(request, 5, "completed", "succeeded", {"message": "l2 completed; quality passed"}))
        sys.stderr.write(
            "run-l2 completed: mass_rel=%s energy_rel=%s\n"
            % (detail.get("massRelativeError"), detail.get("energyRelativeError"))
        )
    else:
        # The task ran to completion; a failed field is reported, never used as valid values.
        _emit(_event(request, 4, "quality", "checking", {"message": "quality failed; field not valid for evaluation"}))
        _emit(_event(request, 5, "completed", "succeeded", {"message": "l2 finished with failed quality; seats omitted"}))
        sys.stderr.write("run-l2 finished with failed quality; seat values omitted\n")
    return 0
