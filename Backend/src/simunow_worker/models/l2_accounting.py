"""L2 result assembly. Does not run OpenFOAM or invent seat temperatures."""

from __future__ import annotations


def evaluate_l2(identity: dict, draft: dict, context: dict) -> dict:
    """Missing samples omit seat_t_c. A zero Celsius value is not unknown."""
    hvac = draft.get("hvac")
    if not hvac:
        raise ValueError("incompleteProject")
    samples = context.get("seatTemperatures")
    omit = samples is None
    return {
        "schemaVersion": 1,
        "identity": identity,
        "state": "succeeded",
        "quality": "notEvaluated",
        "supplyTemperatureC": hvac["supplyTemperatureC"]["value"],
        "setpointC": hvac["setpointC"]["value"],
        "metrics": [
            {
                "name": "seat_t_c",
                "value": None if omit else samples,
                "unit": "C",
                "method": "openfoam_cell_sample",
                "fidelity": "l2",
                "omitted": omit,
            }
        ],
    }
