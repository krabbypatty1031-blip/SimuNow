"""Map a P2 ProjectDraft onto the P1 room JSON that write_idf understands.

Does not invent opaque UA or SHGC. Those stay omitted until the project models them.
"""

from __future__ import annotations

from simunow_worker.models.project import patch_area_m2

_WALL_X = {
    "xMin": lambda size: 0.0,
    "xMax": lambda size: size[0],
    "yMin": lambda size: 0.0,
    "yMax": lambda size: size[1],
}


def _windows(geometry: dict) -> list[dict]:
    """All window openings, in draft order. Doors are not glazed and stay out."""
    return [item for item in geometry.get("openings", []) if item.get("kind") == "window"]


def _window_area_m2(windows: list[dict]) -> float:
    """Total glazed area. The IDF takes ONE east-wall window of this area, so
    adding or widening any window must move the L1 load and the bill."""
    return sum(patch_area_m2(item) for item in windows)


def _qty(node: dict, source: str = "project") -> dict:
    return {
        "value": node["value"],
        "unit": node.get("unit", "1"),
        "source": node.get("source", source),
    }


def project_to_l1_room(draft: dict) -> dict:
    """Build a P1-shaped room. Window area is the wall patch, never the wall width."""
    geometry = draft.get("geometry")
    occupancy = draft.get("occupancy")
    hvac = draft.get("hvac")
    if not geometry or not occupancy or not hvac:
        raise ValueError("incompleteProject")
    windows = _windows(geometry)
    if not windows:
        raise ValueError("project has no window opening")
    # All windows merge into the single IDF window. The band (x/z0/z1) and the
    # declared flux stay from the first window; the AREA is the sum, which is
    # the only L1 entry the east-wall window consumes.
    window = windows[0]
    window_area = _window_area_m2(windows)
    size = (
        geometry["sizeX"]["value"],
        geometry["sizeY"]["value"],
        geometry["sizeZ"]["value"],
    )
    supply_wall = hvac["supply"]["wall"]
    window_wall = window["wall"]
    return {
        "name": draft.get("name", "room"),
        "kind": "room",
        "coordinates": {
            "system": "metre_right_handed_z_up",
            "foam_up_axis": "Y",
            "gravity_contract_m_s2": [0, 0, -9.81],
            "gravity_foam_m_s2": [0, -9.81, 0],
        },
        "assumptions": [
            "omitted: furniture_boxes",
            "omitted: envelope_u_value",
            "omitted: l1.ua_opaque_w_k",
            "omitted: l1.shgc",
            "EnergyPlus constructions are engine defaults, not project envelope",
            "all windows merge into one east-wall window; window area is the sum over windows",
        ],
        "size": {
            "x_m": _qty(geometry["sizeX"]),
            "y_m": _qty(geometry["sizeY"]),
            "z_m": _qty(geometry["sizeZ"]),
        },
        "supply": {
            "t_c": _qty(hvac["supplyTemperatureC"]),
            "u_m_s": _qty(hvac["supplySpeedMs"]),
            "x_m": {"value": _WALL_X[supply_wall](size), "unit": "m", "source": "project"},
            "z0_m": _qty(hvac["supply"]["z0"]),
            "z1_m": _qty(hvac["supply"]["z1"]),
        },
        "return": {
            "x_m": {"value": _WALL_X[hvac["returnTerminal"]["wall"]](size), "unit": "m", "source": "project"},
            "z0_m": _qty(hvac["returnTerminal"]["z0"]),
            "z1_m": _qty(hvac["returnTerminal"]["z1"]),
        },
        "window": {
            "x_m": {"value": _WALL_X[window_wall](size), "unit": "m", "source": "project"},
            "z0_m": _qty(window["z0"]),
            "z1_m": _qty(window["z1"]),
            **({"q_w_m2": _qty(window["heatFluxWm2"])} if window.get("heatFluxWm2") else {}),
        },
        "gains": {
            "n_people": _qty(occupancy["occupantCount"]),
            "people_w": _qty(occupancy["occupantSensibleW"]),
            "lighting_w": _qty(occupancy["lightingW"]),
            "equipment_w": _qty(occupancy["equipmentW"]),
        },
        "seats": [
            {
                "id": seat["id"],
                "x_m": seat["position"]["x"],
                "y_m": seat["position"]["y"],
                "z_m": seat["position"]["z"],
                "source": seat.get("source", "project"),
            }
            for seat in occupancy.get("seats", [])
        ],
        "l1": {
            "t_in_c": _qty(hvac["setpointC"]),
            "infil_m3_s": _qty(hvac["outdoorAirM3s"]),
            # Summed area, not the first window's patch. Adding a window must
            # raise the IDF window load (and with it the electricity cost).
            "window_area_m2": {"value": window_area, "unit": "m2", "source": "project"},
            "cop": _qty(hvac["cop"]),
        },
        # Clock window only. Missing schedule must not become a 24h occupied day here.
        "schedule": {
            "occupancy": _hours(occupancy.get("schedule")),
            "hvac": _hours(hvac.get("schedule") or occupancy.get("schedule")),
        },
    }


def _hours(node: dict | None) -> dict | None:
    if not node:
        return None
    return {
        "kind": node.get("kind", "occupied_hours"),
        "start": node["start"],
        "end": node["end"],
        "source": node.get("source", "project"),
    }
