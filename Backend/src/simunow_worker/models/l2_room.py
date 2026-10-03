"""Map a P2 ProjectDraft onto the P1 room JSON that write_openfoam_room understands.

Does not invent envelope UA, wall temperatures, or quality.pass.
Furniture stays omitted until the P1 loader accepts boxes.
"""

from __future__ import annotations

from simunow_worker.models.project import patch_area_m2

_WALL_X = {
    "xMin": lambda size: 0.0,
    "xMax": lambda size: size[0],
    "yMin": lambda size: 0.0,
    "yMax": lambda size: size[1],
}


def _qty(node: dict, source: str = "project") -> dict:
    return {
        "value": node["value"],
        "unit": node.get("unit", "1"),
        "source": node.get("source", source),
    }


def _assumed(value: float, unit: str) -> dict:
    return {"value": value, "unit": unit, "source": "assumed"}


def _wall_span(wall: str, size: tuple[float, float, float]) -> float:
    """Length of the wall a patch sits on. xMin/xMax run along y; yMin/yMax along x."""
    return size[1] if wall in ("xMin", "xMax") else size[0]


def _band_scale(patch: dict, wall: str, size: tuple[float, float, float]) -> float:
    """Patch width / full wall span.

    The P1 case writer can only make full-wall bands. Scaling velocity and
    flux by this ratio preserves the project's supply m3/s and window W;
    the geometry simplification is recorded in assumptions instead of
    silently changing the physics.
    """
    span = _wall_span(wall, size)
    width = patch["s1"]["value"] - patch["s0"]["value"]
    return width / span


def _windows(geometry: dict) -> list[dict]:
    """All window openings, in draft order. Doors are not glazed and stay out."""
    return [item for item in geometry.get("openings", []) if item.get("kind") == "window"]


def _window_total_w(windows: list[dict]) -> float:
    """Total window heat input, sum of flux x patch area over all windows.

    A window without a declared heatFluxWm2 contributes 0 W; no flux is
    invented for it. Adding or widening any declared window must move the
    L2 field (and with it every seat temperature).
    """
    total = 0.0
    for item in windows:
        flux = item.get("heatFluxWm2")
        if flux:
            total += float(flux["value"]) * patch_area_m2(item)
    return total


def _window_area_m2(windows: list[dict]) -> float:
    """Total glazed area over all windows."""
    return sum(patch_area_m2(item) for item in windows)


def project_to_l2_room(draft: dict) -> dict:
    """Build a P1-shaped L2 room. Supply T is the coil, not the zone setpoint."""
    geometry = draft.get("geometry")
    occupancy = draft.get("occupancy")
    hvac = draft.get("hvac")
    if not geometry or not occupancy or not hvac:
        raise ValueError("incompleteProject")
    windows = _windows(geometry)
    if not windows:
        raise ValueError("project has no window opening")
    # All windows merge into the single full-span band. The band height keeps
    # the first window's z0/z1; the flux is set so the band injects the SUM of
    # every window's declared watts (conservation, not the first window only).
    window = windows[0]
    window_area = _window_area_m2(windows)
    window_w = _window_total_w(windows)
    size = (
        geometry["sizeX"]["value"],
        geometry["sizeY"]["value"],
        geometry["sizeZ"]["value"],
    )
    seats = occupancy.get("seats", [])
    seat_z = seats[0]["position"]["z"] if seats else 1.1
    outdoor = hvac["outdoorAirM3s"]["value"]
    supply_flow = hvac["supplyAirflowM3s"]["value"]
    supply_wall = hvac["supply"]["wall"]
    window_wall = window["wall"]
    supply_scale = _band_scale(hvac["supply"], supply_wall, size)
    # Band flux = total window W / band area, so the single full-span band
    # injects the sum of every window's declared watts. Single-window rooms
    # keep the previous flux bit for bit (width/span cancels the height).
    window_span = _wall_span(window_wall, size)
    window_band_area_m2 = window_span * max(1e-9, window["z1"]["value"] - window["z0"]["value"])
    window_flux = window_w / window_band_area_m2
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
            "P1 first-version L2 case has no furniture boxes",
            "wall temperatures are not invented from UA",
            "supply band spans the full wall; velocity scaled to preserve project supply m3/s",
            "window band spans the full wall; flux scaled to preserve total window W",
            "all windows merge into one band; total window W is the sum over windows",
        ],
        "size": {
            "x_m": _qty(geometry["sizeX"]),
            "y_m": _qty(geometry["sizeY"]),
            "z_m": _qty(geometry["sizeZ"]),
        },
        "mesh": {
            "nx": _assumed(16, "1"),
            "n_span": _assumed(12, "1"),
            "n_height": _assumed(14, "1"),
        },
        "air": {
            "rho": _assumed(1.2, "kg/m3"),
            "cp": _assumed(1006.0, "J/(kg.K)"),
            "nu": _assumed(0.006, "m2/s"),
            "pr": _assumed(0.71, "1"),
            "beta": _assumed(0.0033, "1/K"),
            "t_ref_c": _qty(hvac["setpointC"]),
        },
        "supply": {
            "t_c": _qty(hvac["supplyTemperatureC"]),
            # Band velocity preserves the project's declared supply airflow.
            "u_m_s": {
                "value": hvac["supplySpeedMs"]["value"] * supply_scale,
                "unit": "m/s",
                "source": "project",
            },
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
            # Band flux preserves the SUM of every window's declared watts.
            # Written unconditionally: a room whose windows declare no flux
            # injects a declared 0 W, which is a real statement, not an
            # invented one.
            "q_w_m2": {
                "value": window_flux,
                "unit": "W/m2",
                "source": "project",
            },
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
            for seat in seats
        ],
        "seat_height_m": {"value": seat_z, "unit": "m", "source": "project"},
        # Initial field guess only. Not a solved air temperature.
        "t_init_c": {
            "value": hvac["setpointC"]["value"],
            "unit": "C",
            "source": "assumed",
        },
        "setpoint_c": _qty(hvac["setpointC"]),
        "ventilation": {
            "outdoor_m3_s": _qty(hvac["outdoorAirM3s"]),
            "recirculated_m3_s": {
                "value": max(0.0, supply_flow - outdoor),
                "unit": "m3/s",
                "source": "project",
            },
        },
        # Summed glazed area over all windows, matching the L1 window area.
        "window_area_m2": {"value": window_area, "unit": "m2", "source": "project"},
        "solver": {
            "end_time": _assumed(4000, "1"),
            "monitor_n": _assumed(20, "1"),
            "monitor_dt_k": _assumed(0.05, "K"),
            "monitor_du_m_s": _assumed(0.02, "m/s"),
            "rerun_dt_k": _assumed(0.2, "K"),
        },
        "quality_gates": {
            "mass_rel": _assumed(0.01, "1"),
            "energy_rel": _assumed(0.05, "1"),
        },
    }
