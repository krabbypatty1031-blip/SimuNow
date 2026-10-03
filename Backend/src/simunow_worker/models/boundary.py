"""L1 → L2 inlet/gain DTO. Not a mesh, field, or quality.pass record."""

from __future__ import annotations

from simunow_worker.models.l2_room import l1_metric_w
from simunow_worker.models.project import patch_area_m2


def _terminal(patch: dict) -> dict:
    return {
        "id": patch["id"],
        "wall": patch["wall"],
        "s0": patch["s0"]["value"],
        "s1": patch["s1"]["value"],
        "z0": patch["z0"]["value"],
        "z1": patch["z1"]["value"],
    }


def _windows(geometry: dict) -> list[dict]:
    """All window openings, in draft order. Doors are not glazed and stay out."""
    return [item for item in geometry.get("openings", []) if item.get("kind") == "window"]


def map_l2_boundary(draft: dict, l1: dict | None = None) -> dict:
    """Supply T comes from L1 or the HVAC coil setting, never the zone setpoint."""
    occupancy = draft.get("occupancy")
    hvac = draft.get("hvac")
    geometry = draft.get("geometry")
    if not occupancy or not hvac or not geometry:
        raise ValueError("incompleteProject")
    supply = hvac["supplyTemperatureC"]["value"]
    if l1 and l1.get("supplyTemperatureC") is not None:
        supply = l1["supplyTemperatureC"]
    # Area-weighted mean flux over ALL windows; a window without a declared
    # flux contributes area but 0 W. A single window keeps its own value.
    windows = _windows(geometry)
    window_area = sum(patch_area_m2(item) for item in windows)
    l1_window_w = l1_metric_w(l1, "window_heat_w")
    l1_opaque_w = l1_metric_w(l1, "opaque_heat_w")
    if l1_window_w is not None and window_area > 0:
        window_w = l1_window_w
        flux = window_w / window_area
    else:
        window_w = sum(
            ((item.get("heatFluxWm2") or {}).get("value") or 0.0) * patch_area_m2(item) for item in windows
        )
        flux = window_w / window_area if window_area > 0 else 0.0
    occupant_count = occupancy["occupantCount"]["value"]
    # Per-person sensible × count once. Seats locate people; they are not a second watt source.
    occupant_sensible = occupant_count * occupancy["occupantSensibleW"]["value"]
    outdoor = hvac["outdoorAirM3s"]["value"]
    supply_flow = hvac["supplyAirflowM3s"]["value"]
    return {
        "supplyTemperatureC": supply,
        "setpointC": hvac["setpointC"]["value"],
        "supply": _terminal(hvac["supply"]),
        "returnTerminal": _terminal(hvac["returnTerminal"]),
        "outdoorAirM3s": outdoor,
        # Recirculated return = supply − outdoor. Not a measured return-air meter.
        "recirculatedAirM3s": max(0.0, supply_flow - outdoor),
        "windowHeatFluxWm2": flux,
        "opaqueHeatW": l1_opaque_w,
        "lightingW": occupancy["lightingW"]["value"],
        "equipmentW": occupancy["equipmentW"]["value"],
        "occupantSensibleW": occupant_sensible,
        "occupantCount": occupant_count,
        "heatSources": [
            {"name": "occupants", "watts": occupant_sensible},
            {"name": "lighting", "watts": occupancy["lightingW"]["value"]},
            {"name": "equipment", "watts": occupancy["equipmentW"]["value"]},
        ],
        "omitted": [] if l1_opaque_w is not None else ["envelope_u_value"],
    }
