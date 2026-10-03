"""Code-computed pair diff for the AI report (ADR-021).

Subtraction happens here so every delta the AI quotes is already
evidence. There is no language model in this file: numbers are copied
from the candidate dicts or subtracted from them, never invented.
"""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any

from simunow_worker.models.feasibility import AIR_HIGH_C, AIR_LOW_C


def _basis_mismatch(left: dict, right: dict) -> str | None:
    reasons: list[str] = []
    if left.get("occupantCount") != right.get("occupantCount"):
        reasons.append("人数")
    if left.get("occupiedStart") != right.get("occupiedStart") or left.get("occupiedEnd") != right.get("occupiedEnd"):
        reasons.append("占用时段")
    if left.get("setpointC") != right.get("setpointC"):
        reasons.append("设定温度")
    if left.get("supplyTemperatureC") != right.get("supplyTemperatureC"):
        reasons.append("送风温度")
    if not reasons:
        return None
    return "口径不同（" + "、".join(reasons) + "）"


def _round_half_up(value: float, places: int) -> float:
    quant = Decimal("1").scaleb(-places)
    return float(Decimal(str(value)).quantize(quant, rounding=ROUND_HALF_UP))


def _annual_energy(day_kwh: float) -> float:
    return _round_half_up(day_kwh * 365, 5)


def _annual_cost(day_cost: float) -> float:
    return _round_half_up(day_cost * 365, 3)


def _delta(first: float | None, second: float | None) -> float | None:
    """Second - first, half-up to two decimals. Both sides present or the row stays out."""
    if first is None or second is None:
        return None
    rounded = _round_half_up(second - first, 2)
    # A tiny negative difference rounds to a negative zero; normalise so the
    # evidence JSON never carries "-0.0" for the AI to copy.
    return 0.0 if rounded == 0 else rounded


def _input_changes(first: dict, second: dict) -> list[dict]:
    """Basis levers first, then the supply patch heights this channel carries."""
    changes: list[dict] = []
    left_basis = first.get("basis") or {}
    right_basis = second.get("basis") or {}

    def numeric(field: str, label: str, unit: str, a, b, sentence) -> None:
        if a is None or b is None or a == b:
            return
        changes.append(
            {
                "field": field,
                "label": label,
                "fromValue": float(a),
                "toValue": float(b),
                "unit": unit,
                "sentence": sentence(float(a), float(b)),
            }
        )

    numeric(
        "occupantCount", "人数", "人",
        left_basis.get("occupantCount"), right_basis.get("occupantCount"),
        lambda a, b: f"人数从 {a:.2f} 人改为 {b:.2f} 人",
    )
    # Occupied hours carry clock strings, not one number; the sentence holds the exact times.
    if (
        left_basis.get("occupiedStart") != right_basis.get("occupiedStart")
        or left_basis.get("occupiedEnd") != right_basis.get("occupiedEnd")
    ):
        changes.append(
            {
                "field": "occupiedHours",
                "label": "使用时间",
                "fromValue": None,
                "toValue": None,
                "unit": "",
                "sentence": (
                    f"使用时间从 {left_basis.get('occupiedStart')}–{left_basis.get('occupiedEnd')}"
                    f" 改为 {right_basis.get('occupiedStart')}–{right_basis.get('occupiedEnd')}"
                ),
            }
        )
    numeric(
        "setpointC", "设定温度", "°C",
        left_basis.get("setpointC"), right_basis.get("setpointC"),
        lambda a, b: f"设定温度从 {a:.2f} °C 改为 {b:.2f} °C",
    )
    numeric(
        "supplyTemperatureC", "出风温度", "°C",
        left_basis.get("supplyTemperatureC"), right_basis.get("supplyTemperatureC"),
        lambda a, b: f"出风温度从 {a:.2f} °C 改为 {b:.2f} °C",
    )
    numeric(
        "supplyZ0M", "出风口下沿", "m",
        first.get("supplyZ0"), second.get("supplyZ0"),
        lambda a, b: f"出风口下沿从 {a:.2f} m 改为 {b:.2f} m",
    )
    numeric(
        "supplyZ1M", "出风口上沿", "m",
        first.get("supplyZ1"), second.get("supplyZ1"),
        lambda a, b: f"出风口上沿从 {a:.2f} m 改为 {b:.2f} m",
    )
    return changes


def _result_deltas(first: dict, second: dict) -> list[dict]:
    """Energy, comfort, flow dimensions. The Swift pack adds more fields;
    this channel covers the flat numbers it actually carries."""
    deltas: list[dict] = []
    currency = first.get("currency") or second.get("currency") or ""

    def row(dimension: str, field: str, label: str, unit: str, a, b) -> None:
        if a is None or b is None:
            return
        deltas.append(
            {
                "dimension": dimension,
                "field": field,
                "label": label,
                "first": float(a),
                "second": float(b),
                "delta": _delta(float(a), float(b)),
                "unit": unit,
            }
        )

    first_energy = first.get("dayEnergyKWh")
    second_energy = second.get("dayEnergyKWh")
    first_cost = first.get("dayCost")
    second_cost = second.get("dayCost")
    row("energy", "dayEnergyKWh", "代表日用电", "kWh", first_energy, second_energy)
    row("energy", "dayCost", "代表日电费", currency, first_cost, second_cost)
    row(
        "energy", "annualEnergyKWh", "全年用电", "kWh",
        _annual_energy(first_energy) if first_energy is not None else None,
        _annual_energy(second_energy) if second_energy is not None else None,
    )
    row(
        "energy", "annualCost", "全年电费", currency,
        _annual_cost(first_cost) if first_cost is not None else None,
        _annual_cost(second_cost) if second_cost is not None else None,
    )
    row("comfort", "seatTMinC", "座位最凉", "°C", first.get("seatTMinC"), second.get("seatTMinC"))
    row("comfort", "seatPassRatio", "合适的座位", "", first.get("seatPassRatio"), second.get("seatPassRatio"))
    return deltas


def pair_diff(candidates: list[dict]) -> dict | None:
    """First two pins only; a single scheme has nothing to subtract."""
    if len(candidates) < 2:
        return None
    first, second = candidates[0], candidates[1]
    return {
        "firstName": first.get("name", "方案一"),
        "secondName": second.get("name", "方案二"),
        "inputChanges": _input_changes(first, second),
        "resultDeltas": _result_deltas(first, second),
        "basisMismatchReason": _basis_mismatch(first.get("basis") or {}, second.get("basis") or {}),
    }


def _evidence_run(candidate: dict) -> dict[str, Any]:
    ratio = candidate.get("seatPassRatio")
    omitted = candidate.get("quality") != "passed" or ratio is None
    row: dict[str, Any] = {
        "name": candidate.get("name", ""),
        "runID": candidate["runID"],
        "scenarioID": candidate.get("scenarioID", candidate["runID"]),
        "inputHash": candidate["inputHash"],
        "quality": candidate.get("quality", "notEvaluated"),
        "seatBandLowC": AIR_LOW_C,
        "seatBandHighC": AIR_HIGH_C,
        "seatPassRatio": None if omitted else ratio,
        "seatPassRatioOmitted": omitted,
    }
    if candidate.get("l1RunID"):
        row["l1RunID"] = candidate["l1RunID"]
    if candidate.get("seatTMinC") is not None and not omitted:
        row["seatTMinC"] = candidate["seatTMinC"]
    if candidate.get("dayEnergyKWh") is not None and not omitted:
        row["dayEnergyKWh"] = candidate["dayEnergyKWh"]
    if candidate.get("dayCost") is not None and not omitted:
        row["dayCost"] = candidate["dayCost"]
    if candidate.get("currency"):
        row["currency"] = candidate["currency"]
    if candidate.get("supplyZ0") is not None:
        row["supplyZ0M"] = candidate["supplyZ0"]
    if candidate.get("supplyZ1") is not None:
        row["supplyZ1M"] = candidate["supplyZ1"]
    row["occupiedDaysPerYear"] = 365
    if row.get("dayEnergyKWh") is not None:
        row["annualEnergyKWh"] = _annual_energy(row["dayEnergyKWh"])
    if row.get("dayCost") is not None:
        row["annualCost"] = _annual_cost(row["dayCost"])
    return row


def build_evidence(candidates: list[dict]) -> dict[str, Any]:
    """CamelCase evidence pack. Figures are the candidate fields, not a new estimate."""
    return {
        "schemaVersion": 1,
        "candidates": [_evidence_run(item) for item in candidates],
        "pairDiff": pair_diff(candidates),
        "tariffReference": _tariff_reference(candidates),
        "comfortAssumptions": [],
    }


def _tariff_reference(candidates: list[dict]) -> str:
    for candidate in candidates:
        if candidate.get("tariffReference"):
            return str(candidate["tariffReference"])
        for line in candidate.get("assumptions") or []:
            if "电价" in line:
                return line
    return "无电价来源"
