"""Representative-day L1 accounting. Does not run EnergyPlus or invent envelope watts."""

from __future__ import annotations

import json

from .task import TaskProtocolError, is_safe_snapshot_path, sha256_hex
from .weather import mmdd, resolved_weather

REPRESENTATIVE_DAY = {"kind": "representative_day", "start": "07-15", "end": "07-15"}


def representative_day(draft: dict) -> dict:
    stamp = mmdd(*resolved_weather(draft))
    return {"kind": "representative_day", "start": stamp, "end": stamp}


def schedule_hash(draft: dict) -> str | None:
    """Hash only occupied-hour objects so a weather file cannot stand in for a schedule."""
    occupancy = (draft.get("occupancy") or {}).get("schedule")
    hvac = (draft.get("hvac") or {}).get("schedule")
    payload: dict = {}
    if occupancy:
        payload["occupancy"] = occupancy
    if hvac:
        payload["hvac"] = hvac
    if not payload:
        return None
    return sha256_hex(json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def _period(schedule: dict | None) -> dict | None:
    if not schedule:
        return None
    return {"kind": schedule["kind"], "start": schedule["start"], "end": schedule["end"]}


def evaluate_l1(identity: dict, draft: dict, context: dict) -> dict:
    """Build a SimulationResult. Missing weather omits loads; a zero watt is not unknown."""
    hvac = draft.get("hvac")
    if not hvac:
        raise ValueError("incompleteProject")
    weather_path = context.get("weatherPath")
    if weather_path is not None and not is_safe_snapshot_path(weather_path):
        raise TaskProtocolError(TaskProtocolError.unsafe_snapshot_path)
    digest = schedule_hash(draft)
    declared = context.get("scheduleHash")
    if declared is not None and declared != digest:
        raise TaskProtocolError(TaskProtocolError.hash_mismatch)
    has_weather = weather_path is not None
    cooling = context.get("coolingLoadW") if has_weather else None
    cop = hvac["cop"]["value"]
    electricity = cooling / cop if cooling is not None and cop > 0 else None
    omit_loads = cooling is None or electricity is None
    window_heat = context.get("windowHeatW")
    opaque_heat = context.get("opaqueHeatW")
    omit_window = window_heat is None
    omit_opaque = opaque_heat is None
    occupancy_schedule = (draft.get("occupancy") or {}).get("schedule")
    return {
        "schemaVersion": 1,
        "identity": identity,
        "state": "succeeded",
        "quality": "notEvaluated",
        "period": representative_day(draft),
        "weatherPath": weather_path,
        "weatherHash": context.get("weatherHash") if has_weather else None,
        "supplyTemperatureC": hvac["supplyTemperatureC"]["value"],
        "setpointC": hvac["setpointC"]["value"],
        "schedule": _period(occupancy_schedule),
        "hvacSchedule": _period(hvac.get("schedule")),
        "scheduleHash": digest,
        "metrics": [
            {
                "name": "q_cool_w",
                "value": None if omit_loads else cooling,
                "unit": "W",
                "method": "equivalent_ideal_loads",
                "fidelity": "l1",
                "omitted": omit_loads,
            },
            {
                "name": "p_elec_w",
                "value": None if omit_loads else electricity,
                "unit": "W",
                "method": "equivalent_ideal_loads",
                "fidelity": "l1",
                "omitted": omit_loads,
            },
            {
                "name": "annual_kwh",
                "value": None,
                "unit": "kWh",
                "method": "not_modeled",
                "fidelity": "l1",
                "omitted": True,
            },
            {
                "name": "window_heat_w",
                "value": None if omit_window else window_heat,
                "unit": "W",
                "method": "energyplus_window_heat",
                "fidelity": "l1",
                "omitted": omit_window,
                "reason": None if not omit_window else "EnergyPlus did not report window heat for this run",
            },
            {
                "name": "opaque_heat_w",
                "value": None if omit_opaque else opaque_heat,
                "unit": "W",
                "method": "energyplus_opaque_conduction",
                "fidelity": "l1",
                "omitted": omit_opaque,
                "reason": None if not omit_opaque else "EnergyPlus did not report opaque conduction for this run",
            },
        ],
    }
