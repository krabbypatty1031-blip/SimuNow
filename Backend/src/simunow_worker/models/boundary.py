"""L1 → L2 inlet/gain DTO. Not a mesh, field, or quality.pass record."""

from __future__ import annotations


def _terminal(patch: dict) -> dict:
    return {
        "id": patch["id"],
        "wall": patch["wall"],
        "s0": patch["s0"]["value"],
        "s1": patch["s1"]["value"],
        "z0": patch["z0"]["value"],
        "z1": patch["z1"]["value"],
    }


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
    window = next((item for item in geometry.get("openings", []) if item.get("kind") == "window"), None)
    flux = ((window or {}).get("heatFluxWm2") or {}).get("value", 0.0)
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
        "lightingW": occupancy["lightingW"]["value"],
        "equipmentW": occupancy["equipmentW"]["value"],
        "occupantSensibleW": occupant_sensible,
        "occupantCount": occupant_count,
        "heatSources": [
            {"name": "occupants", "watts": occupant_sensible},
            {"name": "lighting", "watts": occupancy["lightingW"]["value"]},
            {"name": "equipment", "watts": occupancy["equipmentW"]["value"]},
        ],
        "omitted": ["envelope_u_value"],
    }
