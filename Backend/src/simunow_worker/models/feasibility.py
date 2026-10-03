"""Demo seat gates for a quality-passed L2 field.

The gates are a product demo, not a standards certification. Coverage is
pass_count / eval_count and must not be reported as a measured satisfaction
rate. A field that did not pass quality omits every feasibility metric:
the ratio is never filled with 0 just because the field is missing.
"""

from __future__ import annotations

from typing import Any

# Sitting air band versus the 26 °C zone setpoint. 24.5 °C is the worst-seat pivot.
AIR_LOW_C = 23.0
AIR_HIGH_C = 26.0
BAND_CENTER_C = 24.5
SPEED_GATE_M_S = 0.25
PMV_LIMIT = 0.5

# ISO 7730 air applicability. Outside it the seat is not a failure and not
# in the denominator; the exclusion is disclosed on the ratio reason.
ISO_AIR_LOW_C = 10.0
ISO_AIR_HIGH_C = 30.0
ISO_SPEED_HIGH_M_S = 1.0

METHOD = "l2_seat_gate"
NOT_MODELED = "not_modeled"
OMIT_REASON = "not evaluable: no quality-passed seat samples"

# Counts stay numeric. Seat id and gate text ride in `reason` because a
# ResultMetric value is a number.
METRIC_SPECS = (
    ("seat_pass_ratio", "1"),
    ("seat_pass_count", "count"),
    ("seat_eval_count", "count"),
    ("worst_seat_id", "id"),
    ("worst_seat_reason", "text"),
    ("infeasibleReason", "text"),
)


def _metric(name: str, unit: str, value: float | None, *, omitted: bool, reason: str | None) -> dict:
    row: dict[str, Any] = {
        "name": name,
        "value": None if omitted else value,
        "unit": unit,
        "method": NOT_MODELED if omitted else METHOD,
        "fidelity": "l2",
        "omitted": omitted,
    }
    if reason:
        row["reason"] = reason
    return row


def _omitted_all(reason: str) -> list[dict]:
    return [_metric(name, unit, None, omitted=True, reason=reason) for name, unit in METRIC_SPECS]


def _failed_gates(row: dict) -> list[str]:
    """Gates this seat missed. Absent PMV is not a miss."""
    gates: list[str] = []
    temperature = float(row["tC"])
    speed = float(row["uMag"])
    if not AIR_LOW_C <= temperature <= AIR_HIGH_C:
        gates.append("温度门")
    # Inclusive upper bound: 0.25 m/s still passes. Low-speed seats use the
    # same cut; the absolute-error flag does not exempt or auto-fail them.
    if speed > SPEED_GATE_M_S:
        gates.append("风速门")
    pmv = row.get("pmv")
    if pmv is not None and not -PMV_LIMIT <= float(pmv) <= PMV_LIMIT:
        gates.append("PMV门")
    return gates


def _split(rows: list[dict]) -> tuple[list[dict], list[dict]]:
    """(evaluated, excluded).

    Omitted and out-of-ISO-air seats never enter the denominator. If some
    remaining seats carry a PMV, a sibling without one was dropped by the
    comfort applicability check and is excluded the same way. When no seat
    has a PMV, that gate is simply not in play and does not fail anyone.
    """
    excluded: list[dict] = []
    candidates: list[dict] = []
    for row in rows:
        if row.get("omitted"):
            excluded.append(row)
            continue
        try:
            temperature = float(row["tC"])
            speed = float(row["uMag"])
        except (KeyError, TypeError, ValueError):
            excluded.append(row)
            continue
        if not (ISO_AIR_LOW_C <= temperature <= ISO_AIR_HIGH_C and 0.0 <= speed <= ISO_SPEED_HIGH_M_S):
            excluded.append(row)
            continue
        candidates.append(row)

    any_pmv = any(row.get("pmv") is not None for row in candidates)
    evaluated: list[dict] = []
    for row in candidates:
        if any_pmv and row.get("pmv") is None:
            excluded.append(row)
            continue
        evaluated.append(row)
    return evaluated, excluded


def _worst(evaluated: list[dict]) -> dict:
    """Largest |tC - 24.5 °C|; higher speed wins a tie."""
    return max(
        evaluated,
        key=lambda row: (abs(float(row["tC"]) - BAND_CENTER_C), float(row["uMag"])),
    )


def feasibility_metrics(seat_rows: list[dict] | None, *, quality_passed: bool) -> list[dict]:
    """Coverage metrics for one field. Missing field → omitted, never ratio 0."""
    if not quality_passed or not seat_rows:
        return _omitted_all(OMIT_REASON)

    evaluated, excluded = _split(seat_rows)
    if not evaluated:
        ids = ", ".join(str(row.get("id")) for row in excluded) or "none"
        return _omitted_all(f"not evaluable: no seat inside the model domain (excluded: {ids}; 不计入分母)")

    pass_count = 0
    hit_gates: list[str] = []
    for row in evaluated:
        gates = _failed_gates(row)
        if gates:
            for gate in gates:
                if gate not in hit_gates:
                    hit_gates.append(gate)
        else:
            pass_count += 1

    eval_count = len(evaluated)
    ratio = pass_count / eval_count
    worst = _worst(evaluated)
    worst_gates = _failed_gates(worst)
    if worst_gates:
        worst_reason = "、".join(worst_gates)
    else:
        # A fully covered field still names the seat farthest from band center.
        worst_reason = "偏离温度带中心 24.5 °C 最大"
    if worst.get("lowSpeedAbsoluteError"):
        worst_reason += "；低速绝对误差"

    notes: list[str] = []
    if excluded:
        ids = ", ".join(str(row.get("id")) for row in excluded)
        notes.append(f"排除 {len(excluded)} 座（域外或 omitted，不计入分母）：{ids}")
    low_speed = [str(row.get("id")) for row in evaluated if row.get("lowSpeedAbsoluteError")]
    if low_speed:
        notes.append("低速绝对误差座位仍用风速门：" + ", ".join(low_speed))
    shared_note = "；".join(notes) if notes else None

    if pass_count == 0:
        # Name the gates. Do not invent a recommended scheme.
        infeasible_omitted = False
        infeasible_reason = "、".join(hit_gates)
    else:
        infeasible_omitted = True
        infeasible_reason = "未触发：已有座位通过模型门"

    values: dict[str, tuple[float | None, bool, str | None]] = {
        "seat_pass_ratio": (ratio, False, shared_note),
        "seat_pass_count": (float(pass_count), False, shared_note),
        "seat_eval_count": (float(eval_count), False, shared_note),
        "worst_seat_id": (None, False, str(worst.get("id"))),
        "worst_seat_reason": (None, False, worst_reason),
        "infeasibleReason": (None, infeasible_omitted, infeasible_reason),
    }
    return [
        _metric(name, unit, values[name][0], omitted=values[name][1], reason=values[name][2])
        for name, unit in METRIC_SPECS
    ]
