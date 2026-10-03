"""Seat samples in contract Z-up, °C. Near-zero speed uses absolute error notes."""

from __future__ import annotations

import logging
import math
from typing import Any

LOGGER = logging.getLogger("simunow.p1.sample")

LOW_SPEED_M_S = 0.05


def seat_sample(
    *,
    seat_id: str,
    x: float,
    y: float,
    z: float,
    t_k: float,
    ux: float,
    uy: float,
    uz: float,
) -> dict[str, Any]:
    """One seat in public coordinates. U components are already contract-frame."""
    u_mag = math.sqrt(ux * ux + uy * uy + uz * uz)
    sample: dict[str, Any] = {
        "id": seat_id,
        "x": x,
        "y": y,
        "z": z,
        "T_C": t_k - 273.15,
        "U_mag": u_mag,
        "U": {"x": ux, "y": uy, "z": uz},
    }
    if u_mag < LOW_SPEED_M_S:
        sample["abs_error_m_s"] = True
        sample["note"] = f"|U|<{LOW_SPEED_M_S} m/s; use absolute speed error, not a huge percent"
        LOGGER.debug("low speed seat %s U=%.4f", seat_id, u_mag)
    return sample


def seat_deltas(first: list[dict[str, Any]], second: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Pair seats by id so a mesh-order change is not a 'recommendation'."""
    by_id = {str(item["id"]): item for item in second}
    rows: list[dict[str, Any]] = []
    for item in first:
        other = by_id.get(str(item["id"]))
        if other is None:
            rows.append({"id": item["id"], "dT_K": None, "dU_mag": None, "status": "missing"})
            continue
        d_t = abs(float(item["T_C"]) - float(other["T_C"]))
        d_u = abs(float(item["U_mag"]) - float(other["U_mag"]))
        row: dict[str, Any] = {
            "id": item["id"],
            "dT_K": d_t,
            "dU_mag": d_u,
            "status": "ok",
            "abs_error_m_s": bool(item.get("abs_error_m_s") or other.get("abs_error_m_s") or min(float(item["U_mag"]), float(other["U_mag"])) < LOW_SPEED_M_S),
        }
        rows.append(row)
    return rows
