"""Typical-year calendar day. The EPW is TMY, not a live forecast; no 29 Feb."""

from __future__ import annotations

DEFAULT_WEATHER = {
    "month": 7,
    "day": 15,
    "source": "assumed",
    "reference": "Hong Kong CityUHK typical meteorological year, not a live forecast",
}

_MONTH_LENGTHS = (0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)


def is_valid_typical_year_day(month: int, day: int) -> bool:
    return 1 <= month <= 12 and 1 <= day <= _MONTH_LENGTHS[month]


def resolved_weather(draft: dict) -> tuple[int, int]:
    """Return (month, day). Missing weather is still 15 July, not 'no day'."""
    raw = draft.get("weather") if isinstance(draft.get("weather"), dict) else {}
    try:
        month = int(raw.get("month") if raw.get("month") is not None else DEFAULT_WEATHER["month"])
        day = int(raw.get("day") if raw.get("day") is not None else DEFAULT_WEATHER["day"])
    except (TypeError, ValueError) as exc:
        raise ValueError("weather month and day must be integers") from exc
    if not is_valid_typical_year_day(month, day):
        raise ValueError("weather day is not a valid typical-year calendar day (no 29 Feb)")
    return month, day


def mmdd(month: int, day: int) -> str:
    return f"{month:02d}-{day:02d}"
