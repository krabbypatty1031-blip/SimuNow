"""ADR-014 representative-day tariff.

Energy is ``p_elec_w / 1000 × occupied hours``, rounded half-up to 0.00001 kWh.
Cost is that energy times the tariff, rounded half-up to currency millis (0.001).
1033.112 W × 10 h × 1.2 HKD/kWh locks at 10.33112 kWh and 12.397 HKD.

Missing electric power or occupied hours omits energy and cost. A missing
tariff omits only the cost. Neither omission is stored as 0. There is no
``annual_kwh`` and no ``payback_years``: one occupied day is not a year, and
retrofit quotes stay 「待报价」.
"""

from __future__ import annotations

from decimal import Decimal, ROUND_HALF_UP

DEMO_TARIFF = {
    "pricePerKWh": 1.2,
    "currency": "HKD",
    "source": "assumed",
    "reference": "比赛演示假设，非真实电价",
}


def _minutes(text: str | None) -> int | None:
    if not text:
        return None
    if text == "24:00":
        return 24 * 60
    parts = text.split(":")
    if len(parts) != 2 or len(parts[0]) != 2 or len(parts[1]) != 2:
        return None
    try:
        hour = int(parts[0])
        minute = int(parts[1])
    except ValueError:
        return None
    if not (0 <= hour <= 23 and 0 <= minute <= 59):
        return None
    return hour * 60 + minute


def occupied_hours(start: str | None, end: str | None) -> Decimal | None:
    """Clock window only. 08:00–18:00 is 10 h, not 24 h and not 365 days."""
    start_m = _minutes(start)
    end_m = _minutes(end)
    if start_m is None or end_m is None or end_m <= start_m:
        return None
    return Decimal(end_m - start_m) / Decimal(60)


def _quantize(value: Decimal, places: str) -> Decimal:
    return value.quantize(Decimal(places), rounding=ROUND_HALF_UP)


def _has_price(tariff: dict | None) -> bool:
    if not tariff or tariff.get("pricePerKWh") is None:
        return False
    currency = str(tariff.get("currency") or "").strip()
    return bool(currency) and Decimal(str(tariff["pricePerKWh"])) >= 0


def representative_day_cost(
    electric_power_w: float | None,
    occupied_start: str | None,
    occupied_end: str | None,
    tariff: dict | None,
) -> dict:
    """Build a day-cost object. Omitted numbers stay None."""
    hours = occupied_hours(occupied_start, occupied_end)
    energy = None
    cost = None
    currency = None
    if electric_power_w is not None and hours is not None:
        energy = _quantize(Decimal(str(electric_power_w)) / Decimal(1000) * hours, "0.00001")
        if _has_price(tariff):
            cost = _quantize(energy * Decimal(str(tariff["pricePerKWh"])), "0.001")
            currency = tariff["currency"]
    return {
        "electric_power_w": None if electric_power_w is None else float(electric_power_w),
        "occupied_hours": None if hours is None else float(hours),
        "energy_kwh": None if energy is None else float(energy),
        "cost": None if cost is None else float(cost),
        "currency": currency,
        "energy_omitted": energy is None,
        "cost_omitted": cost is None,
        "retrofit_quote": "待报价",
    }


def savings_hkd(high: dict, low: dict, basis_mismatch: str | None) -> float | None:
    """Subtract two L1 day costs. A basis mismatch returns None, not a scaled watt."""
    if basis_mismatch:
        return None
    if high.get("cost") is None or low.get("cost") is None:
        return None
    if high.get("electric_power_w") is None or low.get("electric_power_w") is None:
        return None
    delta = _quantize(Decimal(str(high["cost"])) - Decimal(str(low["cost"])), "0.001")
    return float(delta)
