"""Structured recommendation cards.

Code classifies operation / comfort / retrofit. There is no language model
here: numbers are copied from the candidate dicts, and a missing quote stays
「待报价」 with no payback field.
"""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP
from typing import Any

from simunow_worker.models.feasibility import AIR_HIGH_C, AIR_LOW_C


def _passed(candidate: dict) -> bool:
    return candidate.get("quality") == "passed" and candidate.get("seatPassRatio") is not None


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


def _same_basis(candidates: list[dict]) -> list[dict]:
    if not candidates:
        return []
    lead = candidates[0].get("basis") or {}
    return [item for item in candidates if _basis_mismatch(lead, item.get("basis") or {}) is None]


def _number(candidate: dict, key: str) -> float | None:
    value = candidate.get(key)
    if value is None:
        return None
    return float(value)


def _explanation(card_id: str, title: str, detail: str, candidates: list[dict]) -> dict:
    return {
        "id": card_id,
        "kind": "explanation",
        "title": title,
        "detail": detail,
        "citedRunIDs": [item["runID"] for item in candidates],
        "qualityPassed": False,
        "assumptions": [],
    }


def _assumptions(candidates: list[dict]) -> list[str]:
    lines: list[str] = []
    for candidate in candidates:
        for line in candidate.get("assumptions") or []:
            if line not in lines:
                lines.append(line)
        quote = candidate.get("retrofitQuote")
        if quote and quote not in lines:
            lines.append(quote)
    return lines


def _comfort(candidates: list[dict]) -> dict | None:
    if len(candidates) < 2:
        return None
    changed: list[dict] = []
    for candidate in candidates:
        for other in candidates:
            if candidate["runID"] == other["runID"]:
                continue
            height_differs = candidate.get("supplyZ0") != other.get("supplyZ0") or candidate.get("supplyZ1") != other.get("supplyZ1")
            metric_differs = False
            for key in ("seatTMinC", "seatPassRatio"):
                left = _number(candidate, key)
                right = _number(other, key)
                if left is not None and right is not None and left != right:
                    metric_differs = True
            if height_differs and metric_differs and candidate not in changed:
                changed.append(candidate)
    if len(changed) < 2:
        return None
    return {
        "id": "comfort",
        "kind": "comfort",
        "title": "舒适：送风高度",
        "detail": "同口径下送风口高度不同，座位温度或达标比例（模型）发生变化。质量 passed。舒适与费用分列，不合成单一分数。",
        "citedRunIDs": [item["runID"] for item in changed],
        "qualityPassed": True,
        "assumptions": _assumptions(changed),
    }


def _operation(candidates: list[dict]) -> dict | None:
    priced = [item for item in candidates if item.get("l1RunID") and item.get("dayCost") is not None]
    if len(priced) < 2:
        return None
    low = min(priced, key=lambda item: float(item["dayCost"]))
    high = max(priced, key=lambda item: float(item["dayCost"]))
    saved = round(float(high["dayCost"]) - float(low["dayCost"]), 3)
    lever = "同口径下设定温度、风量与占用仍可调整。"
    if saved == 0:
        detail = lever + "无电费差。"
    else:
        currency = high.get("currency") or ""
        detail = f"{lever}代表日电费相差 {saved:.3f} {currency}（两次 L1 电功率之差，不是系数估算）。"
    return {
        "id": "operation",
        "kind": "operation",
        "title": "运行：代表日电费",
        "detail": detail,
        "citedRunIDs": [item["l1RunID"] for item in priced],
        "qualityPassed": True,
        "assumptions": _assumptions(priced),
    }


def _retrofit(candidates: list[dict]) -> dict:
    assumptions = _assumptions(candidates) + ["更换设备或安装尚无报价，不写回收期"]
    return {
        "id": "retrofit",
        "kind": "retrofit",
        "title": "改造：设备与安装",
        "detail": "更换设备或改安装需要报价。当前结论为待报价。",
        "citedRunIDs": [item["runID"] for item in candidates],
        "qualityPassed": all(item.get("quality") == "passed" for item in candidates),
        "assumptions": assumptions,
        "quoteStatus": "待报价",
    }


def can_export_recommendation(candidates: list[dict]) -> bool:
    """Explanation-only packs stay visible; they are not a recommendation PDF."""
    return any(card["kind"] != "explanation" and card.get("qualityPassed") for card in classify_cards(candidates))


def _mixed_basis_reason(candidates: list[dict]) -> str | None:
    if not candidates:
        return None
    lead = candidates[0].get("basis") or {}
    for item in candidates[1:]:
        reason = _basis_mismatch(lead, item.get("basis") or {})
        if reason:
            return reason
    return None


def classify_cards(candidates: list[dict]) -> list[dict]:
    """Order is constraint, then comfort, then cost. No feasible field yields one explanation."""
    if not candidates:
        return []
    if not any(_passed(item) for item in candidates):
        return [
            _explanation(
                "no-quality-passed-field",
                "无质量通过场",
                "这些 run 没有质量通过的气流场，不能比较座位舒适或代表日费用。",
                candidates,
            )
        ]
    passed = [item for item in candidates if _passed(item)]
    if passed and all(
        (item.get("seatEvalCount") or 0) > 0 and (item.get("seatPassCount") or 0) == 0 for item in passed
    ):
        return [
            _explanation(
                "no-feasible-seats",
                "已评座位均未通过模型门",
                "已评座位全部未通过温度、风速或 PMV 门。这里只说明触犯的约束。",
                passed,
            )
        ]
    if mixed := _mixed_basis_reason(passed):
        # Mixed occupancy or setpoints cannot be ranked as a recommendation.
        return [
            _explanation(
                "basis-mismatch",
                "口径不同",
                mixed + "。不能作为有效推荐。",
                passed,
            )
        ]
    comparable = _same_basis(passed)
    cards: list[dict] = []
    partial = [
        item
        for item in comparable
        if (item.get("seatEvalCount") or 0) > 0 and (item.get("seatPassCount") or 0) < (item.get("seatEvalCount") or 0)
    ]
    if partial:
        cards.append(
            {
                "id": "constraint",
                "kind": "explanation",
                "title": "约束：部分座位未过模型门",
                "detail": "部分已评座位未通过模型门。先看约束，再比较舒适与代表日费用。",
                "citedRunIDs": [item["runID"] for item in partial],
                "qualityPassed": True,
                "assumptions": _assumptions(partial),
            }
        )
    comfort = _comfort(comparable)
    if comfort:
        cards.append(comfort)
    operation = _operation(comparable)
    if operation:
        cards.append(operation)
    if comparable:
        cards.append(_retrofit(comparable))
    return cards


def _tariff_reference(candidates: list[dict]) -> str:
    for candidate in candidates:
        if candidate.get("tariffReference"):
            return str(candidate["tariffReference"])
        for line in candidate.get("assumptions") or []:
            if "电价" in line:
                return line
    return "无电价来源"


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


def _round_half_up(value: float, places: int) -> float:
    quant = Decimal("1").scaleb(-places)
    return float(Decimal(str(value)).quantize(quant, rounding=ROUND_HALF_UP))


def _annual_energy(day_kwh: float) -> float:
    return _round_half_up(day_kwh * 365, 5)


def _annual_cost(day_cost: float) -> float:
    return _round_half_up(day_cost * 365, 3)


def build_evidence(candidates: list[dict]) -> dict[str, Any]:
    """CamelCase evidence pack. Figures are the candidate fields, not a new estimate."""
    return {
        "schemaVersion": 1,
        "candidates": [_evidence_run(item) for item in candidates],
        "cards": classify_cards(candidates),
        "tariffReference": _tariff_reference(candidates),
        "comfortAssumptions": [],
    }
