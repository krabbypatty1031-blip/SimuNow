"""Seat-height horizontal temperature slice in the public contract.

Grid values are nearest solve-mesh cell temperatures - the same source of
truth as seat samples - so display density can never change the physics.
Grid points sit at cell centres of an nx x ny lattice over the floor; a
point outside the fluid (walls, future furniture) is masked invalid and
never joins statistics. A slice file exists only for a quality-passed
field: a failed field has no honest colour to paint.

Wire contract (see Protocols/Schemas/field-slice.schema.json):
- unit: C; coordinateSystem: rightHandedZUp (the public frame, not foam's)
- axisOrder ["y", "x"]: values[j][i] is row j (y) / column i (x)
- JSON is decimal text, so no float-format/endian ambiguity exists today;
  any future binary field must add float format, endianness and hash fields
- valid[j][i] false marks wall/furniture interiors: neutral display, no stats
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from room_input import RoomError, foam_xyz, point_in_fluid, qty

LOGGER = logging.getLogger("simunow.p1.field_slice")


def _nearest_cell(
    px: float,
    py: float,
    pz: float,
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> int:
    """Index of the closest cell centre (foam frame), mirroring seat lookup."""
    best = 0
    best_d = float("inf")
    for index, (x, y, z) in enumerate(zip(cx, cy, cz)):
        dist = (x - px) ** 2 + (y - py) ** 2 + (z - pz) ** 2
        if dist < best_d:
            best_d = dist
            best = index
    return best


def slice_grid(
    room: dict[str, Any],
    *,
    z_m: float,
    spacing_hint_m: float,
    temperature: list[float],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> dict[str, Any]:
    """Cell-centred nearest-cell temperature grid at height z_m.

    Raises RoomError when the slice height is not strictly inside the room.
    """
    lx = qty(room["size"]["x_m"])
    ly = qty(room["size"]["y_m"])
    lz = qty(room["size"]["z_m"])
    if not 0.0 < float(z_m) < lz:
        raise RoomError(f"slice height {z_m} m is outside the room")
    if spacing_hint_m <= 0:
        raise RoomError("slice spacing hint must be positive")
    if not temperature:
        raise RoomError("no cell field to sample the slice from")

    # Cell-centred lattice: nx columns across x, ny rows along y. The hint is
    # a display density knob and can never change the sampled physics.
    nx = max(1, round(lx / float(spacing_hint_m)))
    ny = max(1, round(ly / float(spacing_hint_m)))
    dx = lx / nx
    dy = ly / ny

    values: list[list[float]] = []
    valid: list[list[bool]] = []
    for j in range(ny):
        row_values: list[float] = []
        row_valid: list[bool] = []
        y = (j + 0.5) * dy
        for i in range(nx):
            x = (i + 0.5) * dx
            inside = point_in_fluid(room, x, y, float(z_m))
            row_valid.append(bool(inside))
            if not inside:
                # Masked cells carry no value; they never join statistics.
                row_values.append(0.0)
                continue
            fx, fy, fz = foam_xyz(x, y, float(z_m))
            index = _nearest_cell(fx, fy, fz, cx, cy, cz)
            row_values.append(temperature[index] - 273.15)
        values.append(row_values)
        valid.append(row_valid)

    temps = [
        value
        for row, row_valid in zip(values, valid)
        for value, is_valid in zip(row, row_valid)
        if is_valid
    ]
    stats = {
        "validCount": len(temps),
        "minC": min(temps) if temps else None,
        "maxC": max(temps) if temps else None,
    }
    return {
        "kind": "temperature_slice",
        "quantity": "air_temperature",
        "unit": "C",
        "coordinateSystem": "rightHandedZUp",
        "axisOrder": ["y", "x"],
        "sampleMethod": "nearest_cell",
        "zM": float(z_m),
        "originM": {"x": dx / 2, "y": dy / 2},
        "spacingM": {"x": dx, "y": dy},
        "shape": {"nx": nx, "ny": ny},
        "values": values,
        "valid": valid,
        "stats": stats,
    }


def write_slice(
    run_dir: Path,
    room: dict[str, Any],
    *,
    z_m: float,
    spacing_hint_m: float,
    input_hash: str,
    quality_pass: bool,
    temperature: list[float],
    cx: list[float],
    cy: list[float],
    cz: list[float],
) -> dict[str, Any] | None:
    """Write field-slice.json for a quality-passed field; nothing otherwise.

    A failed field has no valid slice to display, so no file exists rather
    than a plausible-looking coloured plane.
    """
    if not quality_pass:
        LOGGER.info("quality failed; no field slice written")
        return None
    grid = slice_grid(
        room,
        z_m=z_m,
        spacing_hint_m=spacing_hint_m,
        temperature=temperature,
        cx=cx,
        cy=cy,
        cz=cz,
    )
    payload = {
        "schemaVersion": 1,
        **grid,
        "inputHash": input_hash,
        "quality": "passed",
    }
    path = run_dir / "field-slice.json"
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    LOGGER.info(
        "field slice %s: %s valid cells, %.2f..%.2f C",
        path.name,
        payload["stats"]["validCount"],
        payload["stats"]["minC"],
        payload["stats"]["maxC"],
    )
    return payload
