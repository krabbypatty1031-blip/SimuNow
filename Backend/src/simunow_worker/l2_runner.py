"""Write an L2 OpenFOAM case from a P2 snapshot.

Does not invent seat temperatures when the engine is missing. This step does not
run the solver.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from .models.l2_accounting import evaluate_l2
from .models.l2_room import project_to_l2_room
from .models.task import validate_request
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
    import write_openfoam_room as writer

    return writer


def _engines_root() -> Path | None:
    raw = os.environ.get("SIMUNOW_ENGINES_ROOT", "").strip()
    if not raw:
        return None
    root = Path(raw)
    return root if root.is_dir() else None


def _openfoam_wrapper(root: Path) -> Path | None:
    script = root / "openfoam.sh"
    if script.is_file() and os.access(script, os.X_OK):
        return script
    return None


def _write_result(run_dir: Path, result: dict) -> None:
    (run_dir / "result.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


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
    writer = _import_p1()
    writer.write_openfoam_room(room, run_dir / "case")
    _emit(_event(request, 1, "progress", "meshing", {"fraction": 0.2, "monitor": "blockMeshDict"}))

    engines = _engines_root()
    wrapper = _openfoam_wrapper(engines) if engines else None
    if wrapper is None:
        result = evaluate_l2(identity, draft, {"seatTemperatures": None})
        result["state"] = "failed"
        _write_result(run_dir, result)
        _emit(_event(request, 2, "failed", "failed", {"message": "OpenFOAM not configured"}))
        sys.stderr.write("run-l2 failed: OpenFOAM not configured; no invented seat temperature\n")
        return 1

    result = evaluate_l2(identity, draft, {"seatTemperatures": None})
    result["state"] = "failed"
    _write_result(run_dir, result)
    _emit(_event(request, 2, "failed", "failed", {"message": "OpenFOAM solve is not wired"}))
    sys.stderr.write("run-l2 failed: solver not wired; case written without invented temperatures\n")
    return 1
