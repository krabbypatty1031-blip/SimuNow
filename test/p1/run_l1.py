"""Run the P1-04 representative day. Exit 0 iff EnergyPlus completed and q_cool_w > 0."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from room_input import RoomError, input_hash, load_room, qty, window_area_m2
from write_idf import gains_table, l1_window_w, write_idf

P1 = Path(__file__).resolve().parent
TEST_ROOT = P1.parent
REPORT_LATEST = TEST_ROOT / "outputs" / "p1_l1" / "latest.json"
EPW_NAME = "CHN_Hong.Kong.SAR.450070_CityUHK.epw"
PERIOD_S = 24 * 3600

LOGGER = logging.getLogger("simunow.p1.run_l1")


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


def engines_root() -> Path:
    raw = os.environ.get("SIMUNOW_ENGINES_ROOT")
    if not raw:
        raise RoomError("SIMUNOW_ENGINES_ROOT is not set")
    root = Path(raw)
    if not root.is_dir():
        raise RoomError(f"SIMUNOW_ENGINES_ROOT is not a directory: {root}")
    return root


def energyplus_bin(root: Path) -> Path:
    path = root / "EnergyPlus" / "energyplus"
    if not path.is_file():
        raise RoomError(f"EnergyPlus binary missing at $SIMUNOW_ENGINES_ROOT/EnergyPlus/energyplus")
    return path


def epw_path(root: Path) -> Path:
    path = root / "weather" / EPW_NAME
    if not path.is_file():
        raise RoomError(f"EPW missing: weather/{EPW_NAME}")
    return path


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def p_elec_w(q_cool_w: float, cop: float) -> float:
    """Electricity is cooling / COP. Ideal Loads cooling is not a meter."""
    if cop <= 0:
        raise RoomError("COP must be positive")
    return q_cool_w / cop


def _parse_csv(path: Path) -> dict[str, list[float]]:
    if not path.is_file():
        return {}
    with path.open(encoding="utf-8", errors="replace", newline="") as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            return {}
        columns: dict[str, list[float]] = {name: [] for name in header}
        for row in reader:
            for name, cell in zip(header, row):
                try:
                    columns[name].append(float(cell))
                except ValueError:
                    continue
    return columns


def _column(columns: dict[str, list[float]], *needles: str) -> tuple[str | None, list[float]]:
    lowered = [(name, values) for name, values in columns.items()]
    for name, values in lowered:
        hay = name.lower()
        if all(needle.lower() in hay for needle in needles) and values:
            return name, values
    return None, []


def _mean(values: list[float]) -> float | None:
    if not values:
        return None
    return sum(values) / len(values)


def parse_l1_outputs(out_dir: Path, room: dict[str, Any]) -> dict[str, Any]:
    end_txt = (out_dir / "eplusout.end").read_text(encoding="utf-8", errors="replace") if (out_dir / "eplusout.end").is_file() else ""
    completed = "EnergyPlus Completed Successfully" in end_txt
    columns = _parse_csv(out_dir / "eplusout.csv")
    t_name, t_vals = _column(columns, "zone mean air temperature")
    rate_name, rate_vals = _column(columns, "total cooling rate")
    energy_name, energy_vals = _column(columns, "total cooling energy")
    q_cool = None
    q_from = None
    if rate_vals:
        q_cool = _mean(rate_vals)
        q_from = f"mean of {rate_name} [W] over {len(rate_vals)} hourly samples"
    elif energy_vals:
        q_cool = sum(energy_vals) / PERIOD_S
        q_from = f"sum of {energy_name} [J] / {PERIOD_S} s ({len(energy_vals)} hourly samples)"
    cop = qty(room["l1"]["cop"])
    elec = p_elec_w(q_cool, cop) if q_cool is not None else None
    face_t: dict[str, float] = {}
    for name, values in columns.items():
        if "inside face temperature" in name.lower() and values:
            key = name.split(":")[0].strip() if ":" in name else name
            avg = _mean(values)
            if avg is not None:
                face_t[key] = avg
    gain_name, gain_vals = _column(columns, "zone windows total heat gain rate")
    loss_name, loss_vals = _column(columns, "zone windows total heat loss rate")
    window_heat = None
    if gain_vals:
        window_heat = (_mean(gain_vals) or 0.0) - (_mean(loss_vals) or 0.0)
    opaque_heat = _opaque_conduction_w(columns)
    LOGGER.info("L1 completed=%s q_cool_w=%s zone_t=%s", completed, q_cool, _mean(t_vals) if t_vals else None)
    return {
        "energyplus_completed": completed,
        "end": end_txt.strip(),
        "q_cool_w": q_cool,
        "p_elec_w": elec,
        "cop": cop,
        "equivalent": True,
        "model": "equivalent_ideal_loads",
        "capacity": "NoLimit",
        "capacity_note": "未做设备容量校核",
        "zone_mean_air_c": _mean(t_vals) if t_vals else None,
        "q_cool_from": q_from,
        "window_heat_w": window_heat,
        "opaque_heat_w": opaque_heat,
        "period_hours": 24,
        "csv_columns": {
            "zone_t": t_name,
            "cooling_rate": rate_name,
            "cooling_energy": energy_name,
            "window_gain": gain_name,
            "window_loss": loss_name,
        },
        "inside_face_t_c": face_t,
    }


def _opaque_conduction_w(columns: dict[str, list[float]]) -> float | None:
    """Sum hourly-mean inside-face conduction on opaque surfaces.

    Window surfaces stay out: their heat is the Zone Windows Total series.
    Missing columns return None so a 0 W winter day is not confused with
    'EnergyPlus did not write the variable'.
    """
    total = 0.0
    found = False
    for name, values in columns.items():
        hay = name.lower()
        if "inside face conduction heat transfer rate" not in hay or not values:
            continue
        if "eastwin" in hay or "window" in hay:
            continue
        avg = _mean(values)
        if avg is None:
            continue
        total += avg
        found = True
    return total if found else None


def boundary_json(room: dict[str, Any], parsed: dict[str, Any]) -> dict[str, Any]:
    """One BC kind per face. Window is heat_flux; opaque uses inside-face T when present."""
    faces: list[dict[str, Any]] = []
    inside = parsed.get("inside_face_t_c") or {}
    opaque_names = {
        "Floor": "floor",
        "Ceiling": "ceiling",
        "WallS": "wall_s",
        "WallN": "wall_n",
        "WallW": "wall_w",
        "WallE": "wall_e",
    }
    for ep_name, slug in opaque_names.items():
        t_c = inside.get(ep_name) or inside.get(ep_name.upper())
        if t_c is None:
            # Keys sometimes include the zone: "ROOM,FLOOR" — match loosely.
            for key, value in inside.items():
                if ep_name.lower() in key.lower():
                    t_c = value
                    break
        if t_c is None:
            faces.append(
                {
                    "name": slug,
                    "bc_kind": "heat_flux",
                    "q_w_m2": 0.0,
                    "source": "L1 inside-face T missing; L2 walls stay adiabatic",
                }
            )
        else:
            faces.append(
                {
                    "name": slug,
                    "bc_kind": "temperature",
                    "t_c": t_c,
                    "source": "EnergyPlus hourly mean Surface Inside Face Temperature",
                }
            )
    window_area = qty(room["l1"]["window_area_m2"])
    measured = parsed.get("window_heat_w")
    window_w = None
    window_source = "window heat omitted; L2 must not invent weather flux"
    if measured is not None:
        window_w = measured
        window_source = "EnergyPlus Zone Windows Total Heat Gain−Loss hourly mean"
    else:
        try:
            window_w = l1_window_w(room)
            window_source = "L1 UA_window*ΔT + SHGC*solar*A; not combined with a Dirichlet T"
        except (KeyError, TypeError):
            window_w = None
    if window_w is None:
        faces.append(
            {
                "name": "window",
                "bc_kind": "heat_flux",
                "source": window_source,
            }
        )
    else:
        faces.append(
            {
                "name": "window",
                "bc_kind": "heat_flux",
                "q_w_m2": window_w / max(window_area, 1e-9),
                "q_w": window_w,
                "area_m2": window_area,
                "source": window_source,
            }
        )
    kinds = {face["name"]: face["bc_kind"] for face in faces}
    LOGGER.debug("boundary kinds %s", kinds)
    return {
        "input_hash": input_hash(room),
        "coordinates": room["coordinates"]["system"],
        "faces": faces,
        "supply": {
            "t_c": qty(room["supply"]["t_c"]),
            "u_m_s": qty(room["supply"]["u_m_s"]),
            "source": "room_p1.json supply; L1 Ideal Loads does not use this diffuser",
        },
        "note": "each face has exactly one bc_kind",
    }


def build_report(room: dict[str, Any], parsed: dict[str, Any], weather: dict[str, Any]) -> dict[str, Any]:
    table = gains_table(room)
    report = {
        **parsed,
        "input_hash": input_hash(room),
        "weather": weather,
        "gains_table": table,
        "l2_window_area_m2": window_area_m2(room),
        "l1_window_area_m2": qty(room["l1"]["window_area_m2"]),
        "annual_savings_kwh": None,
        "annual_savings_note": "not computed; P1 forbids a fake annual saving",
    }
    return report


def run_energyplus(idf: Path, out_dir: Path, ep: Path, weather: Path, timeout: int = 180) -> subprocess.CompletedProcess[str]:
    out_dir.mkdir(parents=True, exist_ok=True)
    cmd = [str(ep), "-x", "-r", "-w", str(weather), "-d", str(out_dir), str(idf)]
    LOGGER.info("EnergyPlus %s", " ".join(cmd[-6:]))
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="P1-04 EnergyPlus representative day")
    parser.add_argument("--input", default=str(P1 / "fixtures" / "room_p1.json"))
    parser.add_argument("--out", default=None)
    args = parser.parse_args(argv)
    room = load_room(Path(args.input))
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = Path(args.out) if args.out else TEST_ROOT / "outputs" / "p1_l1" / stamp
    run_dir.mkdir(parents=True, exist_ok=True)
    setup_logging(run_dir / "l1.log")
    LOGGER.info("L1 run %s hash=%s", stamp, input_hash(room)[:12])
    (run_dir / "input.json").write_text(json.dumps(room, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (run_dir / "input_hash.txt").write_text(input_hash(room) + "\n", encoding="utf-8")
    try:
        root = engines_root()
        ep = energyplus_bin(root)
        weather = epw_path(root)
    except RoomError as exc:
        LOGGER.error("%s", exc)
        print(str(exc), file=sys.stderr)
        return 1
    idf = write_idf(room, run_dir / "room.idf")
    proc = run_energyplus(idf, run_dir, ep, weather)
    (run_dir / "energyplus.stdout.log").write_text((proc.stdout or "") + "\n" + (proc.stderr or ""), encoding="utf-8")
    parsed = parse_l1_outputs(run_dir, room)
    weather_meta = {
        "epw_name": EPW_NAME,
        "epw_sha256": file_sha256(weather),
        "binary": "$SIMUNOW_ENGINES_ROOT/EnergyPlus/energyplus",
        "note": "Hong Kong EPW RunPeriod 15 Jul; not a DesignDay claimed as weather",
    }
    report = build_report(room, parsed, weather_meta)
    report["energyplus_returncode"] = proc.returncode
    boundary = boundary_json(room, parsed)
    (run_dir / "l1_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    (run_dir / "boundary.json").write_text(json.dumps(boundary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    rel = run_dir.resolve().relative_to(TEST_ROOT.resolve()).as_posix()
    print(rel)
    REPORT_LATEST.parent.mkdir(parents=True, exist_ok=True)
    REPORT_LATEST.write_text(
        json.dumps(
            {
                "run_dir": rel,
                "energyplus_completed": report.get("energyplus_completed"),
                "q_cool_w": report.get("q_cool_w"),
                "p_elec_w": report.get("p_elec_w"),
                "input_hash": report.get("input_hash"),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    ok = bool(report.get("energyplus_completed") and report.get("q_cool_w") and report["q_cool_w"] > 0)
    LOGGER.info("L1 pass=%s q_cool_w=%s p_elec_w=%s", ok, report.get("q_cool_w"), report.get("p_elec_w"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
