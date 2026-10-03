"""L2 result assembly. Does not run OpenFOAM or invent seat temperatures.

Three independent axes: run state (did the pipeline finish), quality state
(did every numerical gate pass), and seat values (only present when quality
passed). A failed gate omits seat values; it never fills them with 0.
"""

from __future__ import annotations

from typing import Any

from simunow_worker.models.comfort import comfort_metrics, omitted_comfort_metrics
from simunow_worker.models.feasibility import feasibility_metrics

SEAT_METRIC_NAMES = ("seat_t_c_min", "seat_t_c_max", "seat_u_mag_max")
SEAT_METRIC_UNITS = {"seat_t_c_min": "C", "seat_t_c_max": "C", "seat_u_mag_max": "m/s"}
SEAT_METHOD = "openfoam_cell_sample"


def _relative_pass(error: Any, gate: Any) -> bool:
    """Both sides must be present; a missing gate is not a zero error."""
    return error is not None and gate is not None and float(error) < float(gate)


def quality_pass(detail: dict | None) -> bool:
    """Every gate must hold. Missing or partial logs never pass."""
    if not isinstance(detail, dict):
        return False
    return bool(
        detail.get("checkMesh") == "ok"
        and detail.get("solverEnded") is True
        and detail.get("monitorsStable") is True
        and _relative_pass(detail.get("massRelativeError"), detail.get("massGate"))
        and _relative_pass(detail.get("energyRelativeError"), detail.get("energyGate"))
    )


def quality_detail(quality: dict | None) -> dict | None:
    """Map a P1 quality.json onto the camelCase contract detail.

    The P1 keys are snake_case internals; the shared wire format is camelCase.
    """
    if not isinstance(quality, dict):
        return None
    monitors = quality.get("monitors") or {}
    mass = quality.get("mass") or {}
    energy = quality.get("energy") or {}
    return {
        "checkMesh": quality.get("checkMesh"),
        "solverEnded": quality.get("solver_end"),
        "monitorsStable": monitors.get("stable"),
        "massRelativeError": mass.get("relative_error"),
        "massGate": mass.get("gate"),
        "energyRelativeError": energy.get("relative_error"),
        "energyGate": energy.get("gate"),
    }


def _seat_metrics(seat_rows: list[dict] | None) -> list[dict]:
    """Honest aggregates over per-seat samples. Not position-level claims."""
    if seat_rows:
        temps = [float(row["tC"]) for row in seat_rows]
        speeds = [float(row["uMag"]) for row in seat_rows]
        values = {
            "seat_t_c_min": min(temps),
            "seat_t_c_max": max(temps),
            "seat_u_mag_max": max(speeds),
        }
    else:
        values = {name: None for name in SEAT_METRIC_NAMES}
    return [
        {
            "name": name,
            "value": value,
            "unit": SEAT_METRIC_UNITS[name],
            "method": SEAT_METHOD,
            "fidelity": "l2",
            "omitted": value is None,
        }
        for name, value in values.items()
    ]


def evaluate_l2(identity: dict, draft: dict, context: dict) -> dict:
    """Assemble an L2 result. Missing quality omits seats; nothing becomes 0.

    The context already carries the contract-shaped qualityDetail (the runner
    maps the P1 quality.json); a missing log stays notEvaluated instead of
    failing, because the two axes are independent.
    """
    hvac = draft.get("hvac")
    if not hvac:
        raise ValueError("incompleteProject")
    pipeline_completed = bool(context.get("pipelineCompleted"))
    detail = context.get("qualityDetail")
    passed = pipeline_completed and quality_pass(detail)
    # Seat values exist only for a quality-passed field. A failed field omits them.
    seat_rows = context.get("seatSamples") if passed else None
    # Comfort needs MRT/RH/clo/met on top of the field's air T and speed.
    # Missing comfort inputs keep PMV omitted with a reason, never PMV=0.
    if seat_rows is None:
        comfort_rows: list[dict] = omitted_comfort_metrics(
            "not evaluable: no quality-passed seat samples"
        )
    else:
        # Annotate PMV first so the seat gates can see it. A missing PMV
        # does not fail a seat; an out-of-domain seat stays out of the ratio.
        seat_rows, comfort_rows = comfort_metrics(seat_rows, context.get("comfortInputs"))
    # Append only. Quality gates above are unchanged. No passed field → omit, never 0.
    feasibility_rows = feasibility_metrics(seat_rows, quality_passed=passed)
    if not pipeline_completed or detail is None:
        quality_state = "notEvaluated"
    elif passed:
        quality_state = "passed"
    else:
        quality_state = "failed"
    return {
        "schemaVersion": 1,
        "identity": identity,
        "state": "succeeded" if pipeline_completed else "failed",
        "quality": quality_state,
        "qualityDetail": detail,
        "supplyTemperatureC": hvac["supplyTemperatureC"]["value"],
        "setpointC": hvac["setpointC"]["value"],
        "seatSamples": seat_rows,
        "metrics": _seat_metrics(seat_rows) + comfort_rows + feasibility_rows,
    }
