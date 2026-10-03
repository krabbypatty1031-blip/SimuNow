"""Quality-gated velocity glyphs and streamlines for display.

Samples the same nearest-cell U field as seat samples, so glyph spacing and
streamline count can never change the physics. A failed field writes no
file. Glyph length is a display scale chosen by the App; this file only
stores physical metres per second.

The P1 writer always places the CFD inlet on the x=0 wall as a full-span
band. Seeds start just inside that solved inlet, not at a schematic AC box
that the mesh does not contain.
"""

from __future__ import annotations

import json
import logging
import math
from pathlib import Path
from typing import Any

from field_slice import _nearest_cell
from room_input import RoomError, contract_xyz, foam_xyz, point_in_fluid, qty, room_box

LOGGER = logging.getLogger("simunow.p1.field_flow")

# Display density only. Nearest-cell lookup stays on the solve mesh.
GLYPH_SPACING_HINT_M = 0.75
STREAMLINE_STEP_M = 0.12
STREAMLINE_MAX_STEPS = 48
INLET_INSET_M = 0.08
MIN_SPEED_M_S = 1e-4


def sample_velocity(
    x: float,
    y: float,
    z: float,
    velocity: list[tuple[float, float, float]],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> tuple[float, float, float]:
    """Contract-frame U of the nearest solve-mesh cell."""
    fx, fy, fz = foam_xyz(x, y, z)
    index = _nearest_cell(fx, fy, fz, cx, cy, cz)
    return contract_xyz(*velocity[index])


def glyph_grid(
    room: dict[str, Any],
    *,
    z_m: float,
    spacing_hint_m: float,
    velocity: list[tuple[float, float, float]],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> list[dict[str, float]]:
    """Coarse seat-height arrows. Masked cells are omitted, never stored as 0."""
    lx, ly, lz = room_box(room)
    if not 0.0 < float(z_m) < lz:
        raise RoomError(f"flow height {z_m} m is outside the room")
    if spacing_hint_m <= 0:
        raise RoomError("glyph spacing hint must be positive")
    if not velocity:
        raise RoomError("no cell field to sample flow from")

    nx = max(1, round(lx / float(spacing_hint_m)))
    ny = max(1, round(ly / float(spacing_hint_m)))
    dx = lx / nx
    dy = ly / ny
    glyphs: list[dict[str, float]] = []
    for j in range(ny):
        y = (j + 0.5) * dy
        for i in range(nx):
            x = (i + 0.5) * dx
            if not point_in_fluid(room, x, y, float(z_m)):
                continue
            ux, uy, uz = sample_velocity(x, y, float(z_m), velocity, cx, cy, cz)
            mag = math.sqrt(ux * ux + uy * uy + uz * uz)
            if mag < MIN_SPEED_M_S:
                continue
            glyphs.append(
                {
                    "x": x,
                    "y": y,
                    "z": float(z_m),
                    "ux": ux,
                    "uy": uy,
                    "uz": uz,
                    "mag": mag,
                }
            )
    return glyphs


def inlet_seeds(room: dict[str, Any]) -> list[tuple[float, float, float]]:
    """Just inside the solved xmin inlet band, plus a few seat-height seeds."""
    lx, ly, lz = room_box(room)
    z0 = qty(room["supply"]["z0_m"])
    z1 = qty(room["supply"]["z1_m"])
    z_mid = 0.5 * (z0 + z1)
    seat_z = float(room["seats"][0]["z_m"]) if room.get("seats") else min(1.1, 0.4 * lz)
    ys = [ly * t for t in (0.2, 0.35, 0.5, 0.65, 0.8)]
    seeds: list[tuple[float, float, float]] = []
    for y in ys:
        seeds.append((INLET_INSET_M, y, z_mid))
    for x, y in ((0.35 * lx, 0.35 * ly), (0.65 * lx, 0.35 * ly), (0.35 * lx, 0.65 * ly), (0.65 * lx, 0.65 * ly)):
        seeds.append((x, y, seat_z))
    return [(x, y, z) for x, y, z in seeds if point_in_fluid(room, x, y, z)]


def integrate_streamline(
    room: dict[str, Any],
    start: tuple[float, float, float],
    *,
    velocity: list[tuple[float, float, float]],
    cx: list[float],
    cy: list[float],
    cz: list[float],
    sign: float = 1.0,
) -> list[dict[str, float]]:
    """RK2 polyline. Stops at solids or still air; never jumps through a wall."""
    x, y, z = start
    points: list[dict[str, float]] = []
    for _ in range(STREAMLINE_MAX_STEPS):
        if not point_in_fluid(room, x, y, z):
            break
        ux, uy, uz = sample_velocity(x, y, z, velocity, cx, cy, cz)
        mag = math.sqrt(ux * ux + uy * uy + uz * uz)
        if mag < MIN_SPEED_M_S:
            break
        points.append({"x": x, "y": y, "z": z, "mag": mag})
        hx, hy, hz = ux / mag, uy / mag, uz / mag
        mx = x + sign * 0.5 * STREAMLINE_STEP_M * hx
        my = y + sign * 0.5 * STREAMLINE_STEP_M * hy
        mz = z + sign * 0.5 * STREAMLINE_STEP_M * hz
        if not point_in_fluid(room, mx, my, mz):
            break
        ux2, uy2, uz2 = sample_velocity(mx, my, mz, velocity, cx, cy, cz)
        mag2 = math.sqrt(ux2 * ux2 + uy2 * uy2 + uz2 * uz2)
        if mag2 < MIN_SPEED_M_S:
            break
        x = x + sign * STREAMLINE_STEP_M * ux2 / mag2
        y = y + sign * STREAMLINE_STEP_M * uy2 / mag2
        z = z + sign * STREAMLINE_STEP_M * uz2 / mag2
    return points


def build_flow(
    room: dict[str, Any],
    *,
    z_m: float,
    velocity: list[tuple[float, float, float]],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> dict[str, Any]:
    glyphs = glyph_grid(
        room,
        z_m=z_m,
        spacing_hint_m=GLYPH_SPACING_HINT_M,
        velocity=velocity,
        cx=cx,
        cy=cy,
        cz=cz,
    )
    lines: list[dict[str, Any]] = []
    for index, seed in enumerate(inlet_seeds(room), start=1):
        points = integrate_streamline(room, seed, velocity=velocity, cx=cx, cy=cy, cz=cz)
        if len(points) < 2:
            continue
        lines.append({"id": f"SL{index}", "points": points})

    mags = [item["mag"] for item in glyphs]
    for line in lines:
        mags.extend(point["mag"] for point in line["points"])
    return {
        "kind": "velocity_overlay",
        "quantity": "air_velocity",
        "unit": "m/s",
        "coordinateSystem": "rightHandedZUp",
        "sampleMethod": "nearest_cell",
        "streamlineMethod": "rk2_nearest_cell",
        "zM": float(z_m),
        "glyphs": glyphs,
        "lines": lines,
        "stats": {
            "glyphCount": len(glyphs),
            "lineCount": len(lines),
            "minMag": min(mags) if mags else None,
            "maxMag": max(mags) if mags else None,
        },
    }


def write_flow(
    run_dir: Path,
    room: dict[str, Any],
    *,
    z_m: float,
    input_hash: str,
    quality_pass: bool,
    velocity: list[tuple[float, float, float]],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> dict[str, Any] | None:
    """Write field-flow.json for a quality-passed field; nothing otherwise."""
    if not quality_pass:
        LOGGER.info("quality failed; no field flow written")
        return None
    payload = {
        "schemaVersion": 1,
        **build_flow(room, z_m=z_m, velocity=velocity, cx=cx, cy=cy, cz=cz),
        "inputHash": input_hash,
        "quality": "passed",
    }
    path = run_dir / "field-flow.json"
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    LOGGER.info(
        "field flow %s: %s glyphs, %s lines, max |U|=%s",
        path.name,
        payload["stats"]["glyphCount"],
        payload["stats"]["lineCount"],
        payload["stats"]["maxMag"],
    )
    return payload
