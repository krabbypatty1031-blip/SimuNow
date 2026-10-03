"""One-shot P1 room: input → mesh → solve → quality. Exit 0 iff quality.pass."""

from __future__ import annotations

import argparse
import json
import logging
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from field_slice import write_slice
from foam_io import latest_time, parse_scalar_field, parse_vector_field
from quality import inlet_conduction_w, mass_energy_from_fluxes
from room_input import (
    RoomError,
    contract_xyz,
    foam_xyz,
    inlet_area_m2,
    input_hash,
    load_room,
    point_in_fluid,
    qty,
    window_area_m2,
)
from sample_seats import seat_sample
from write_openfoam_room import write_openfoam_room

P1 = Path(__file__).resolve().parent
TEST_ROOT = P1.parent


def _openfoam_sh() -> Path:
    """Resolve the OpenFOAM wrapper.

    SIMUNOW_ENGINES_ROOT (the App passes the user-selected engines directory)
    overrides the repo path: engine files an app copies into its own
    container get quarantined by macOS and the sandboxed app can neither exec
    nor remove the mark (2026-10-03 hand test), so the wrapper must run in
    place from the user's tree. Without the variable the repo path keeps the
    CLI behavior unchanged.
    """
    root = os.environ.get("SIMUNOW_ENGINES_ROOT", "").strip()
    if root:
        return Path(root) / "openfoam.sh"
    return TEST_ROOT / "engines" / "openfoam.sh"


OPENFOAM_SH = _openfoam_sh()
REPORT_LATEST = TEST_ROOT / "outputs" / "p1_room" / "latest.json"

LOGGER = logging.getLogger("simunow.p1.run_room")


def setup_logging(log_path: Path) -> None:
    LOGGER.setLevel(logging.DEBUG)
    LOGGER.handlers.clear()
    formatter = logging.Formatter("%(asctime)s | %(levelname)s | %(message)s")
    stream = logging.StreamHandler(sys.stderr)
    stream.setLevel(logging.INFO)
    stream.setFormatter(formatter)
    LOGGER.addHandler(stream)
    handle = logging.FileHandler(log_path)
    handle.setLevel(logging.DEBUG)
    handle.setFormatter(formatter)
    LOGGER.addHandler(handle)
    LOGGER.propagate = False


def _of(case: Path, args: list[str], log_path: Path, timeout: int) -> subprocess.CompletedProcess[str]:
    if not OPENFOAM_SH.is_file():
        # Name the resolved wrapper path: env-override and repo modes differ.
        raise RoomError(f"openfoam.sh is missing at {OPENFOAM_SH}")
    command = [str(OPENFOAM_SH), str(case), *args]
    LOGGER.info("OpenFOAM %s", " ".join(args[:4]))
    proc = subprocess.run(command, capture_output=True, text=True, timeout=timeout, check=False)
    log_path.write_text((proc.stdout or "") + "\n" + (proc.stderr or ""), encoding="utf-8")
    return proc


def _parse_checkmesh(text: str) -> str:
    """OpenFOAM prints 'Mesh OK.' only when geometry checks passed."""
    if "Mesh OK." in text and "***Failed" not in text:
        return "ok"
    return "failed"


def _probe_table(path: Path) -> list[list[float]]:
    rows: list[list[float]] = []
    if not path.is_file():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        parts = line.replace("(", " ").replace(")", " ").split()
        try:
            rows.append([float(item) for item in parts])
        except ValueError:
            continue
    return rows


def _monitor_stable(values: list[float], n_last: int, limit: float) -> tuple[bool, float]:
    if len(values) < 2:
        return False, float("inf")
    window = values[-n_last:] if len(values) >= n_last else values
    span = max(window) - min(window)
    return span < limit, span


def _nearest_cell(
    px: float,
    py: float,
    pz: float,
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> int:
    best = 0
    best_d = float("inf")
    for index, (x, y, z) in enumerate(zip(cx, cy, cz)):
        dist = (x - px) ** 2 + (y - py) ** 2 + (z - pz) ** 2
        if dist < best_d:
            best_d = dist
            best = index
    return best


def _phi_sum(post: Path, name: str) -> float | None:
    matches = sorted(post.glob(f"{name}/**/surfaceFieldValue.dat"))
    if not matches:
        return None
    rows = _probe_table(matches[-1])
    if not rows:
        return None
    return rows[-1][-1]


def sample_seats(
    room: dict[str, Any],
    *,
    temperature: list[float],
    velocity: list[tuple[float, float, float]],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> dict[str, Any]:
    """Contract seat samples from solve-mesh cell fields.

    Every seat is accounted for: a seat outside the fluid is omitted with a
    reason, never fabricated as 0 or nearest-wall air. Seat T and |U| are the
    nearest solve-mesh cell values, so display-slice density can never change
    the reported seat numbers.
    """
    seats_out: list[dict[str, Any]] = []
    omitted: list[dict[str, Any]] = []
    for seat in room["seats"]:
        x, y, z = float(seat["x_m"]), float(seat["y_m"]), float(seat["z_m"])
        if not point_in_fluid(room, x, y, z):
            omitted.append({"id": str(seat["id"]), "omitted": True, "reason": "not_in_fluid"})
            LOGGER.error("seat %s outside the fluid; sample omitted, not invented", seat["id"])
            continue
        fx, fy, fz = foam_xyz(x, y, z)
        index = _nearest_cell(fx, fy, fz, cx, cy, cz)
        u_foam = velocity[index]
        ux, uy, uz = contract_xyz(u_foam[0], u_foam[1], u_foam[2])
        seats_out.append(
            seat_sample(seat_id=str(seat["id"]), x=x, y=y, z=z, t_k=temperature[index], ux=ux, uy=uy, uz=uz)
        )
    return {"seats": seats_out, "omitted_seats": omitted}


def run_pipeline(room: dict[str, Any], run_dir: Path, timeout: int = 600) -> dict[str, Any]:
    """Mesh, gate, solve, sample. quality.pass is false unless every gate holds."""
    run_dir.mkdir(parents=True, exist_ok=True)
    digest = input_hash(room)
    (run_dir / "input.json").write_text(json.dumps(room, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (run_dir / "input_hash.txt").write_text(digest + "\n", encoding="utf-8")
    case = write_openfoam_room(room, run_dir / "case")

    block = _of(case, ["blockMesh"], run_dir / "blockMesh.log", 120)
    if block.returncode != 0:
        raise RoomError("blockMesh failed")
    check = _of(case, ["checkMesh"], run_dir / "checkMesh.log", 120)
    check_status = _parse_checkmesh((run_dir / "checkMesh.log").read_text(encoding="utf-8", errors="replace"))
    LOGGER.info("checkMesh %s", check_status)
    quality: dict[str, Any] = {
        "pass": False,
        "input_hash": digest,
        "checkMesh": check_status,
        "solver_end": False,
        "pyvista": False,
        "slice_note": "未用 PyVista；切片来自 postProcess cuttingPlane VTK",
    }
    if check_status != "ok":
        LOGGER.error("checkMesh failed; not solving")
        (run_dir / "quality.json").write_text(json.dumps(quality, indent=2) + "\n", encoding="utf-8")
        return quality

    solve = _of(
        case,
        [
            "bash",
            "-lc",
            "buoyantBoussinesqSimpleFoam -case /work; echo $? > /work/solver.rc; "
            "cat /sys/fs/cgroup/memory.peak > /work/cgroup_memory_peak 2>/dev/null || true",
        ],
        run_dir / "solver.log",
        timeout,
    )
    solver_log = (run_dir / "solver.log").read_text(encoding="utf-8", errors="replace")
    shutil.copy(run_dir / "solver.log", case / "solver.log")
    quality["solver_end"] = "End" in solver_log and "FOAM FATAL" not in solver_log
    rc_file = case / "solver.rc"
    if rc_file.is_file():
        quality["solver_rc"] = int(rc_file.read_text(encoding="utf-8").strip() or "1")
    else:
        quality["solver_rc"] = solve.returncode
    peak = case / "cgroup_memory_peak"
    if peak.is_file() and peak.read_text(encoding="utf-8").strip().isdigit():
        quality["cgroup_rss_mb"] = int(peak.read_text(encoding="utf-8").strip()) / (1024 * 1024)

    if quality["solver_rc"] != 0 or not quality["solver_end"]:
        LOGGER.error("solver did not end cleanly")
        (run_dir / "quality.json").write_text(json.dumps(quality, indent=2) + "\n", encoding="utf-8")
        return quality

    _of(case, ["postProcess", "-func", "writeCellCentres", "-latestTime"], run_dir / "centres.log", 120)

    n_last = int(qty(room["solver"]["monitor_n"]))
    dt_lim = qty(room["solver"]["monitor_dt_k"])
    du_lim = qty(room["solver"]["monitor_du_m_s"])
    probe_t = _probe_table(case / "postProcessing" / "probes" / "0" / "T")
    probe_u = _probe_table(case / "postProcessing" / "probes" / "0" / "U")
    t_outlet = [row[2] for row in probe_t if len(row) > 2]
    t_far = [row[3] for row in probe_t if len(row) > 3]
    u_inlet = [row[1] for row in probe_u if len(row) > 1]
    t_ok, t_span = _monitor_stable([value - 273.15 for value in t_far], n_last, dt_lim) if t_far else (False, float("inf"))
    u_ok, u_span = _monitor_stable(u_inlet, n_last, du_lim) if u_inlet else (False, float("inf"))
    quality["monitors"] = {
        "n_last": n_last,
        "dt_k_gate": dt_lim,
        "du_m_s_gate": du_lim,
        "far_seat_dt_k": t_span,
        "inlet_u_span_m_s": u_span,
        "stable": bool(t_ok and u_ok),
        "note": "residuals alone are not a pass",
    }
    quality["gates"] = {
        "monitor_dt_k": dt_lim,
        "monitor_du_m_s": du_lim,
        "rerun_dt_k": qty(room["solver"]["rerun_dt_k"]),
        "mass_rel": qty(room["quality_gates"]["mass_rel"]),
        "energy_rel": qty(room["quality_gates"]["energy_rel"]),
    }

    time_dir = latest_time(case)
    temperature = parse_scalar_field((time_dir / "T").read_text(encoding="utf-8", errors="replace"))
    velocity = parse_vector_field((time_dir / "U").read_text(encoding="utf-8", errors="replace"))
    cx = parse_scalar_field((time_dir / "Cx").read_text(encoding="utf-8", errors="replace"))
    cy = parse_scalar_field((time_dir / "Cy").read_text(encoding="utf-8", errors="replace"))
    cz = parse_scalar_field((time_dir / "Cz").read_text(encoding="utf-8", errors="replace"))

    phi_in = _phi_sum(case / "postProcessing", "inletFlow")
    phi_out = _phi_sum(case / "postProcessing", "outletFlow")
    area_in = inlet_area_m2(room)
    vdot_in = abs(phi_in) if phi_in is not None else qty(room["supply"]["u_m_s"]) * area_in
    vdot_out = abs(phi_out) if phi_out is not None else vdot_in
    # Enthalpy uses phi-weighted patch T. A single outlet probe is the short-circuit mixed-cup
    # that P0 showed can look closed or open for the wrong reason.
    t_in_patch = _phi_sum(case / "postProcessing", "inletT")
    t_out_patch = _phi_sum(case / "postProcessing", "outletT")
    t_supply_k = t_in_patch if t_in_patch is not None else qty(room["supply"]["t_c"]) + 273.15
    t_return_k = t_out_patch if t_out_patch is not None else (t_outlet[-1] if t_outlet else t_supply_k + 5.0)
    quality["t_supply_k"] = t_supply_k
    quality["t_return_k"] = t_return_k
    quality["t_return_source"] = "outlet_phi_weighted" if t_out_patch is not None else "outlet_probe"
    # Measured, never assumed 0: under a weak jet the fixedValue supply plane
    # absorbs hundreds of watts from the warm stratified ceiling layer.
    q_inlet_cond_w = inlet_conduction_w(
        case=case,
        time_dir=time_dir,
        t_supply_k=t_supply_k,
        rho=qty(room["air"]["rho"]),
        cp=qty(room["air"]["cp"]),
        nu=qty(room["air"]["nu"]),
        pr=qty(room["air"]["pr"]),
    )
    budget = mass_energy_from_fluxes(
        vdot_in=vdot_in,
        vdot_out=vdot_out,
        t_supply_k=t_supply_k,
        t_return_k=t_return_k,
        rho=qty(room["air"]["rho"]),
        cp=qty(room["air"]["cp"]),
        q_people_w=qty(room["gains"]["n_people"]) * qty(room["gains"]["people_w"]),
        q_lights_w=qty(room["gains"]["lighting_w"]),
        q_equip_w=qty(room["gains"]["equipment_w"]),
        q_window_w=qty(room["window"]["q_w_m2"]) * window_area_m2(room),
        q_inlet_cond_w=q_inlet_cond_w,
        mass_gate=qty(room["quality_gates"]["mass_rel"]),
        energy_gate=qty(room["quality_gates"]["energy_rel"]),
    )
    quality["mass"] = budget["mass"]
    quality["energy"] = budget["energy"]
    quality["phi_in_m3_s"] = phi_in
    quality["phi_out_m3_s"] = phi_out

    sampled = sample_seats(
        room,
        temperature=temperature,
        velocity=velocity,
        cx=cx,
        cy=cy,
        cz=cz,
    )
    seats_out = sampled["seats"]
    samples = {
        "count": len(seats_out),
        "seats": seats_out,
        "omitted_seats": sampled["omitted_seats"],
        "input_hash": digest,
        "pyvista": False,
    }
    vtk = list((case / "postProcessing").glob("seatSlice/**/*.vtp")) + list(
        (case / "postProcessing").glob("seatSlice/**/*.vtk")
    )
    samples["slice_files"] = [path.relative_to(run_dir).as_posix() for path in vtk]
    (run_dir / "samples.json").write_text(json.dumps(samples, indent=2) + "\n", encoding="utf-8")

    # Sampled + omitted must cover every seat; a silent drop is a failure.
    quality["pass"] = bool(
        quality["checkMesh"] == "ok"
        and quality["solver_end"]
        and quality["monitors"]["stable"]
        and budget["mass"]["pass"]
        and budget["energy"]["pass"]
        and len(seats_out) + len(samples["omitted_seats"]) == len(room["seats"])
    )
    LOGGER.info("quality.pass=%s mass=%s energy=%s", quality["pass"], budget["mass"]["pass"], budget["energy"]["pass"])

    # Seat-height temperature slice for display. Same nearest-cell source of
    # truth as seat samples; written only for a quality-passed field, so a
    # failed field never gets a plausible-looking coloured plane.
    if room["seats"]:
        write_slice(
            run_dir,
            room,
            z_m=float(room["seats"][0]["z_m"]),
            spacing_hint_m=0.25,
            input_hash=digest,
            quality_pass=quality["pass"],
            temperature=temperature,
            cx=cx,
            cy=cy,
            cz=cz,
        )
    (run_dir / "quality.json").write_text(json.dumps(quality, indent=2) + "\n", encoding="utf-8")
    return quality


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="P1-03 room pipeline")
    parser.add_argument("--input", default=str(P1 / "fixtures" / "room_p1.json"))
    parser.add_argument("--nx", type=int, default=None)
    parser.add_argument("--n-span", type=int, default=None, dest="n_span")
    parser.add_argument("--n-height", type=int, default=None, dest="n_height")
    parser.add_argument("--out", default=None)
    args = parser.parse_args(argv)
    room = load_room(Path(args.input))
    if args.nx or args.n_span or args.n_height:
        from room_input import set_mesh

        mesh = room["mesh"]
        room = set_mesh(
            room,
            nx=args.nx or int(qty(mesh["nx"])),
            n_span=args.n_span or int(qty(mesh["n_span"])),
            n_height=args.n_height or int(qty(mesh["n_height"])),
        )
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = Path(args.out) if args.out else TEST_ROOT / "outputs" / "p1_room" / stamp
    run_dir.mkdir(parents=True, exist_ok=True)
    setup_logging(run_dir / "room.log")
    LOGGER.info("room run %s hash=%s", stamp, input_hash(room)[:12])
    try:
        quality = run_pipeline(room, run_dir)
    except (RoomError, subprocess.TimeoutExpired) as exc:
        LOGGER.error("%s", exc)
        print(str(exc), file=sys.stderr)
        return 1
    rel = run_dir.resolve().relative_to(TEST_ROOT.resolve()).as_posix()
    print(rel)
    REPORT_LATEST.parent.mkdir(parents=True, exist_ok=True)
    REPORT_LATEST.write_text(
        json.dumps({"run_dir": rel, "quality_pass": quality["pass"], "input_hash": quality["input_hash"]}, indent=2)
        + "\n",
        encoding="utf-8",
    )
    return 0 if quality.get("pass") else 1


if __name__ == "__main__":
    sys.exit(main())
