"""P1 room JSON: quantities, canonical hash, Z-up ↔ OpenFOAM Y-up."""

from __future__ import annotations

import hashlib
import json
import logging
from copy import deepcopy
from pathlib import Path
from typing import Any

LOGGER = logging.getLogger("simunow.p1.room")

# Display-only keys never enter input_hash; mesh density must.
_HASH_DROP = {"camera", "display", "ui", "notes_ui"}


class RoomError(Exception):
    """Room input cannot be hashed or converted."""


def qty(node: Any) -> float:
    """Read a number or a {value, unit, source} object."""
    if isinstance(node, dict) and "value" in node:
        return float(node["value"])
    if isinstance(node, (int, float)):
        return float(node)
    raise RoomError(f"not a quantity: {node!r}")


def load_room(path: Path) -> dict[str, Any]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RoomError("room JSON must be an object")
    coords = data.get("coordinates") or {}
    if coords.get("system") != "metre_right_handed_z_up":
        raise RoomError("room coordinates.system must be metre_right_handed_z_up")
    if coords.get("foam_up_axis") != "Y":
        raise RoomError("P1 adapter only implements foam_up_axis=Y")
    assumptions = data.get("assumptions") or []
    obstacles = data.get("obstacles") or []
    if obstacles:
        # Furnished rooms (2026-10-04): furniture blocks whole mesh cells.
        # The disclosure must be present so no furnished case can pose as
        # the pre-furniture "omitted" contract.
        if not any("furniture boxes enter the L2 case as blocked cells" in str(item) for item in assumptions):
            raise RoomError("furnished rooms must disclose furniture boxes as blocked cells")
    elif not any("omitted: furniture_boxes" in str(item) for item in assumptions):
        raise RoomError("first-version rooms must assume omitted: furniture_boxes")
    LOGGER.debug("loaded room %s", data.get("name"))
    return data


def _strip_for_hash(node: Any) -> Any:
    if isinstance(node, dict):
        return {
            key: _strip_for_hash(value)
            for key, value in node.items()
            if key not in _HASH_DROP
        }
    if isinstance(node, list):
        return [_strip_for_hash(item) for item in node]
    return node


def canonical_bytes(room: dict[str, Any]) -> bytes:
    """UTF-8 JSON with sorted keys. Key order in the file must not change the hash."""
    payload = _strip_for_hash(deepcopy(room))
    payload.pop("input_hash", None)
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return text.encode("utf-8")


def input_hash(room: dict[str, Any]) -> str:
    digest = hashlib.sha256(canonical_bytes(room)).hexdigest()
    LOGGER.debug("input_hash %s", digest)
    return digest


def set_mesh(room: dict[str, Any], nx: int, n_span: int, n_height: int) -> dict[str, Any]:
    """Copy the room with a new mesh so P1-05 hashes differ only by density."""
    out = deepcopy(room)
    out["mesh"] = {
        "nx": {"value": int(nx), "unit": "1", "source": "mesh_study"},
        "n_span": {"value": int(n_span), "unit": "1", "source": "mesh_study"},
        "n_height": {"value": int(n_height), "unit": "1", "source": "mesh_study"},
    }
    return out


def foam_xyz(x: float, y: float, z: float) -> tuple[float, float, float]:
    """Contract Z-up (x,y,z) → OpenFOAM Y-up (x, z, y)."""
    return (x, z, y)


def contract_xyz(fx: float, fy: float, fz: float) -> tuple[float, float, float]:
    """OpenFOAM Y-up → contract Z-up."""
    return (fx, fz, fy)


def room_box(room: dict[str, Any]) -> tuple[float, float, float]:
    return qty(room["size"]["x_m"]), qty(room["size"]["y_m"]), qty(room["size"]["z_m"])


def internal_gain_w(room: dict[str, Any]) -> float:
    gains = room["gains"]
    return qty(gains["n_people"]) * qty(gains["people_w"]) + qty(gains["lighting_w"]) + qty(gains["equipment_w"])


def window_rects(room: dict[str, Any]) -> list[dict[str, Any]]:
    """Per-window rectangles: windows[] (L2 room, P4-07) or legacy single window.

    Why two shapes coexist: the L1 room JSON (l1_room.py) keeps ONE merged
    window without s0/s1 — EnergyPlus only consumes the summed area, so its
    contract is unchanged. The L2 room JSON carries every window separately
    because the case writer meshes each rectangle as its own patch.
    """
    windows = room.get("windows")
    if isinstance(windows, list) and windows:
        return windows
    return []


def window_area_m2(room: dict[str, Any]) -> float:
    """Glazed area actually entering the case.

    windows[]: the SUM of per-window rectangle areas (P4-07 geometry
    fidelity — each patch injects only over its own rectangle).
    Legacy single window (L1 room, no s0/s1): the full-span band, so the
    write_idf diagnostic column keeps its pre-P4-07 value bit for bit.
    """
    windows = window_rects(room)
    if windows:
        return sum(
            abs(qty(item["s1_m"]) - qty(item["s0_m"])) * abs(qty(item["z1_m"]) - qty(item["z0_m"]))
            for item in windows
        )
    span = qty(room["size"]["y_m"])
    height = qty(room["window"]["z1_m"]) - qty(room["window"]["z0_m"])
    return abs(span * height)


def window_total_w(room: dict[str, Any]) -> float:
    """Total window heat input, Σ per-window q × area (P4-07).

    Only defined for windows[] rooms: the energy gate accounts the watts the
    per-window fixedGradient patches actually inject. A window with no
    declared flux carries a declared 0 W, never an invented one.
    """
    total = 0.0
    for item in window_rects(room):
        area = abs(qty(item["s1_m"]) - qty(item["s0_m"])) * abs(qty(item["z1_m"]) - qty(item["z0_m"]))
        total += qty(item["q_w_m2"]) * area
    return total



def inlet_area_m2(room: dict[str, Any]) -> float:
    span = qty(room["size"]["y_m"])
    height = qty(room["supply"]["z1_m"]) - qty(room["supply"]["z0_m"])
    return abs(span * height)


def point_in_fluid(room: dict[str, Any], x: float, y: float, z: float, margin: float = 1e-6) -> bool:
    """Reject wall/outside samples so 0 is never used as room air.

    Furniture boxes (2026-10-04) block whole cells, so their AABBs are not
    fluid either: a sample inside a box is omitted upstream, never snapped
    to a neighbouring cell that could read as room air.
    """
    lx, ly, lz = room_box(room)
    if not (margin < x < lx - margin and margin < y < ly - margin and margin < z < lz - margin):
        return False
    for box in obstacle_boxes(room):
        if box["x0"] + margin < x < box["x1"] - margin and box["y0"] + margin < y < box["y1"] - margin and box["z0"] + margin < z < box["z1"] - margin:
            return False
    return True


def obstacle_boxes(room: dict[str, Any]) -> list[dict[str, Any]]:
    """Contract Z-up AABBs of the furniture the L2 case blocks cells for.

    The App's placement rules keep boxes inside the room and clear of
    windows/terminals; this reader still validates bounds so a hand-edited
    or migrated draft is an honest error, never a case with furniture
    hanging outside the mesh.
    """
    lx, ly, lz = room_box(room)
    boxes: list[dict[str, Any]] = []
    for index, item in enumerate(room.get("obstacles") or []):
        x0, y0, z0 = qty(item["x0_m"]), qty(item["y0_m"]), qty(item["z0_m"])
        x1, y1, z1 = qty(item["x1_m"]), qty(item["y1_m"]), qty(item["z1_m"])
        if not (0 <= x0 < x1 <= lx + 1e-9 and 0 <= y0 < y1 <= ly + 1e-9 and 0 <= z0 < z1 <= lz + 1e-9):
            raise RoomError(
                f"obstacle {item.get('id', index)} leaves the room box "
                f"0..{lx:g} x 0..{ly:g} x 0..{lz:g} m"
            )
        boxes.append(
            {
                "id": str(item.get("id", f"F{index + 1}")),
                "kind": str(item.get("kind", "desk")),
                "x0": x0,
                "y0": y0,
                "z0": z0,
                "x1": x1,
                "y1": y1,
                "z1": z1,
            }
        )
    return boxes
