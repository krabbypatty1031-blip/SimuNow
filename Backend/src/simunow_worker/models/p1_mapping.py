"""Map App ProjectDraft JSON onto P1 room scalars. Does not run EnergyPlus or OpenFOAM."""

from __future__ import annotations

from simunow_worker.models.project import patch_area_m2


OMITTED = (
    "l1.ua_opaque_w_k",
    "l1.ua_window_w_k",
    "l1.shgc",
    "weather_file",
    "quality.pass",
)


def _patch(terminal: dict) -> dict:
    return {
        "wall": terminal["wall"],
        "s0_m": terminal["s0"]["value"],
        "s1_m": terminal["s1"]["value"],
        "z0_m": terminal["z0"]["value"],
        "z1_m": terminal["z1"]["value"],
    }


def map_project_to_p1(draft: dict) -> dict:
    """Return P1-shaped fields. Window area uses s0/s1 × z0/z1, not wall width. Never sets quality.pass."""
    geometry = draft["geometry"]
    occupancy = draft["occupancy"]
    hvac = draft["hvac"]
    windows = [item for item in geometry["openings"] if item.get("kind") == "window"]
    if not windows:
        raise ValueError("project has no window opening")
    # First window describes the band; the total glazed area is the SUM over
    # all windows so adding a window moves this mapping like it moves L1.
    window = windows[0]
    window_area = sum(patch_area_m2(item) for item in windows)
    return {
        "name": draft["name"],
        "size": {
            "x_m": geometry["sizeX"]["value"],
            "y_m": geometry["sizeY"]["value"],
            "z_m": geometry["sizeZ"]["value"],
        },
        "supply": {
            **_patch(hvac["supply"]),
            "t_c": hvac["supplyTemperatureC"]["value"],
            "u_m_s": hvac["supplySpeedMs"]["value"],
        },
        "return": _patch(hvac["returnTerminal"]),
        "window": {
            "wall": window["wall"],
            "s0_m": window["s0"]["value"],
            "s1_m": window["s1"]["value"],
            "z0_m": window["z0"]["value"],
            "z1_m": window["z1"]["value"],
            "q_w_m2": (window.get("heatFluxWm2") or {}).get("value", 0),
            # First window's own patch area. The TOTAL is window_area_m2 below.
            "area_m2": patch_area_m2(window),
        },
        "gains": {
            "n_people": occupancy["occupantCount"]["value"],
            "people_w": occupancy["occupantSensibleW"]["value"],
            "lighting_w": occupancy["lightingW"]["value"],
            "equipment_w": occupancy["equipmentW"]["value"],
        },
        "seats": [
            {
                "id": seat["id"],
                "x_m": seat["position"]["x"],
                "y_m": seat["position"]["y"],
                "z_m": seat["position"]["z"],
            }
            for seat in occupancy["seats"]
        ],
        "window_area_m2": window_area,
        "size_x_m": geometry["sizeX"]["value"],
        "size_y_m": geometry["sizeY"]["value"],
        "size_z_m": geometry["sizeZ"]["value"],
        "supply_t_c": hvac["supplyTemperatureC"]["value"],
        "seat_ids": [seat["id"] for seat in occupancy["seats"]],
        "omitted": list(OMITTED),
    }
