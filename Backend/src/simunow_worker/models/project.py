"""Parse the shared project JSON. This is the App contract, not the P1 solver fixture."""

from __future__ import annotations

IDENTITY_KEYS = (
    "schemaVersion",
    "id",
    "name",
    "spaceType",
    "lengthUnit",
    "coordinateSystem",
)
PHYSICAL_KEYS = ("geometry", "occupancy", "hvac")
# Tariff is not a solver input. Keep it on the draft so a saved package round-trips.
OPTIONAL_KEYS = ("costAssumptions", "weather")


def parse_project(payload: dict) -> dict:
    """Return a copy. Missing partitions stay missing; no default room is invented."""
    if not isinstance(payload, dict):
        raise TypeError("project payload must be an object")
    missing = [key for key in IDENTITY_KEYS if key not in payload]
    if missing:
        raise ValueError(f"project identity missing {missing}")
    if payload["lengthUnit"] != "m":
        raise ValueError("lengthUnit must be m")
    if payload["coordinateSystem"] != "rightHandedZUp":
        raise ValueError("coordinateSystem must be rightHandedZUp")
    draft = {key: payload[key] for key in IDENTITY_KEYS}
    for key in PHYSICAL_KEYS:
        if key in payload:
            draft[key] = payload[key]
    for key in OPTIONAL_KEYS:
        if key in payload:
            draft[key] = payload[key]
    return draft


def has_complete_physical_model(draft: dict) -> bool:
    """All three partitions present. Does not mean a solver is configured."""
    return all(draft.get(key) for key in PHYSICAL_KEYS)


def patch_area_m2(patch: dict) -> float:
    """Wall rectangle area from s0/s1 × z0/z1. Values are metres on the wire."""
    width = max(0.0, patch["s1"]["value"] - patch["s0"]["value"])
    height = max(0.0, patch["z1"]["value"] - patch["z0"]["value"])
    return width * height


def supply_airflow_matches_speed(hvac: dict, relative_tolerance: float = 0.05) -> bool:
    """Declared m3/s versus speed × patch area. Tolerance is not a confidence interval."""
    expected = hvac["supplySpeedMs"]["value"] * patch_area_m2(hvac["supply"])
    actual = hvac["supplyAirflowM3s"]["value"]
    if expected == 0:
        return abs(actual) <= relative_tolerance
    return abs(actual - expected) / expected <= relative_tolerance
