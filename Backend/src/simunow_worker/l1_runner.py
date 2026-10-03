"""Run a representative-day EnergyPlus L1 from a P2 snapshot.

Does not invent watts when the engine or weather file is missing.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from .models.l1_accounting import evaluate_l1
from .models.l1_room import project_to_l1_room
from .models.task import TaskProtocolError, is_safe_snapshot_path, sha256_hex, validate_request
from .task_runner import _emit, _event

EPW_NAME = "CHN_Hong.Kong.SAR.450070_CityUHK.epw"


def _repo_root() -> Path:
    cwd = Path.cwd()
    if (cwd / "test" / "p1" / "write_idf.py").is_file():
        return cwd
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "test" / "p1" / "write_idf.py").is_file():
            return parent
    return cwd


def _import_p1():
    p1 = _repo_root() / "test" / "p1"
    if str(p1) not in sys.path:
        sys.path.insert(0, str(p1))
    import run_l1 as l1
    import write_idf as wi

    return l1, wi


def _engines_root() -> Path | None:
    raw = os.environ.get("SIMUNOW_ENGINES_ROOT", "").strip()
    if not raw:
        return None
    root = Path(raw)
    return root if root.is_dir() else None


def _energyplus(root: Path) -> Path | None:
    binary = root / "EnergyPlus" / "energyplus"
    if binary.is_file() and os.access(binary, os.X_OK):
        return binary
    return None


def _resolve_weather(request: dict, root: Path | None) -> tuple[Path | None, str | None]:
    """Package-relative first, then the pinned engines EPW. Absolute home paths are rejected."""
    declared = request.get("weatherPath")
    if declared:
        if not is_safe_snapshot_path(declared):
            raise TaskProtocolError(TaskProtocolError.unsafe_snapshot_path)
        candidates = [
            _repo_root() / declared,
            Path.cwd() / declared,
        ]
        if root is not None:
            candidates.append(root / declared)
            candidates.append(root / "weather" / Path(declared).name)
        for path in candidates:
            if path.is_file():
                return path, sha256_hex(path.read_bytes())
        return None, None
    if root is not None:
        fallback = root / "weather" / EPW_NAME
        if fallback.is_file():
            return fallback, sha256_hex(fallback.read_bytes())
    return None, None


def _write_result(run_dir: Path, result: dict) -> None:
    (run_dir / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _identity(request: dict) -> dict:
    return request["identity"]


def run_l1_task(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(prog="simunow-worker run-l1")
    parser.add_argument("--request", required=True)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args(argv)

    run_dir = Path(args.run_dir)
    run_dir.mkdir(parents=True, exist_ok=True)
    request = json.loads(Path(args.request).read_text(encoding="utf-8"))
    snapshot_path = Path(args.snapshot)
    snapshot = snapshot_path.read_bytes()
    validate_request(request, snapshot)
    draft = json.loads(snapshot.decode("utf-8"))

    sys.stderr.write("run-l1 start run-dir=runs/%s\n" % run_dir.name)
    sys.stderr.flush()
    _emit(_event(request, 0, "accepted", "queued", {"message": "accepted"}))

    identity = _identity(request)
    try:
        room = project_to_l1_room(draft)
    except (ValueError, KeyError, TypeError) as exc:
        _emit(_event(request, 1, "failed", "failed", {"message": f"incomplete project: {exc}"}))
        return 1

    (run_dir / "l1-room.json").write_text(json.dumps(room, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    engines = _engines_root()
    ep = _energyplus(engines) if engines else None
    if ep is None:
        result = evaluate_l1(
            identity,
            draft,
            {"weatherPath": None, "weatherHash": None, "coolingLoadW": None},
        )
        result["state"] = "failed"
        _write_result(run_dir, result)
        _emit(_event(request, 1, "failed", "failed", {"message": "EnergyPlus not configured"}))
        sys.stderr.write("run-l1 failed: EnergyPlus not configured; no invented watts\n")
        return 1

    try:
        weather, weather_hash = _resolve_weather(request, engines)
    except TaskProtocolError:
        _emit(_event(request, 1, "failed", "failed", {"message": "unsafe weather path"}))
        return 1

    if weather is None:
        result = evaluate_l1(
            identity,
            draft,
            {"weatherPath": request.get("weatherPath"), "weatherHash": None, "coolingLoadW": None},
        )
        result["state"] = "failed"
        _write_result(run_dir, result)
        _emit(_event(request, 1, "failed", "failed", {"message": "weather file omitted"}))
        sys.stderr.write("run-l1 failed: weather omitted; cooling not filled with 0\n")
        return 1

    weather_rel = f"weather/{weather.name}"
    _emit(_event(request, 1, "progress", "solving", {"fraction": 0.2, "monitor": "energyplus"}))
    l1, wi = _import_p1()
    idf = wi.write_idf(room, run_dir / "room.idf")
    proc = l1.run_energyplus(idf, run_dir / "energyplus", ep, weather)
    (run_dir / "logs").mkdir(exist_ok=True)
    (run_dir / "logs" / "energyplus.log").write_text((proc.stdout or "") + "\n" + (proc.stderr or ""), encoding="utf-8")
    parsed = l1.parse_l1_outputs(run_dir / "energyplus", room)
    cooling = parsed.get("q_cool_w") if parsed.get("energyplus_completed") else None
    result = evaluate_l1(
        identity,
        draft,
        {
            "weatherPath": weather_rel,
            "weatherHash": weather_hash,
            "coolingLoadW": cooling,
        },
    )
    if not parsed.get("energyplus_completed") or cooling is None:
        result["state"] = "failed"
        _write_result(run_dir, result)
        _emit(_event(request, 2, "failed", "failed", {"message": "EnergyPlus did not complete"}))
        return 1
    _write_result(run_dir, result)
    _emit(_event(request, 2, "progress", "solving", {"fraction": 1.0, "monitor": "energyplus"}))
    _emit(_event(request, 3, "completed", "succeeded", {"message": "l1 completed"}))
    return 0
