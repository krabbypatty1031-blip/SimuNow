"""ISO 7730 seat comfort. Evaluated only with complete, in-range inputs.

PMV/PPD follow the ISO 7730 Annex D normative algorithm (ADR-010: no runtime
dependency; the Annex D BASIC program is ported line by line below, and tests
anchor it to published output of the same algorithm and to the standard's
own Table 2 PPD values). The L2 field supplies per-seat air temperature and
speed; MRT, RH, clo and met must come from outside the field model. Missing
or out-of-applicability inputs stay not evaluable: a reason is reported, a
value is never filled with 0.

Applicability (ISO 7730 Clause 4): M 46..232 W/m2 (0.8..4 met), Icl 0..0.310
m2K/W (0..2 clo), ta 10..30 C, tr 10..40 C, var 0..1 m/s, pa 0..2700 Pa, and
PMV itself only between -2 and +2.
"""

from __future__ import annotations

import math
from typing import Any

# Comfort inputs the field model cannot provide itself.
COMFORT_INPUT_KEYS = ("mrtC", "rhPct", "clo", "met")


def comfort_inputs_from_draft(draft: dict) -> dict | None:
    """Four runner keys from occupancy.comfort. Any missing value stays omitted."""
    comfort = (draft.get("occupancy") or {}).get("comfort")
    if not isinstance(comfort, dict):
        return None
    values: dict[str, float] = {}
    for key in COMFORT_INPUT_KEYS:
        item = comfort.get(key)
        if not isinstance(item, dict) or item.get("value") is None:
            return None
        try:
            values[key] = float(item["value"])
        except (TypeError, ValueError):
            return None
    return values
COMFORT_METRIC_NAMES = ("seat_pmv_min", "seat_pmv_max", "seat_ppd_max")
COMFORT_UNITS = {"seat_pmv_min": "index", "seat_pmv_max": "index", "seat_ppd_max": "%"}
COMFORT_METHOD = "iso7730_pmv"
NOT_MODELED_METHOD = "not_modeled"

# 1 met = 58.15 W/m2 (Annex D uses this constant; ISO text rounds 1 met to
# 58.2 W/m2 in a note, but the normative program uses 58.15).
MET_TO_W_M2 = 58.15


class NotEvaluable(ValueError):
    """Comfort inputs are missing or outside the ISO 7730 applicability."""


# Applicability limits of the PMV index; PMV is not claimed outside them.
APPLICABILITY = {
    "air temperature": ("t_air_c", 10.0, 30.0),
    "radiant temperature": ("t_mrt_c", 10.0, 40.0),
    "air speed": ("v_m_s", 0.0, 1.0),
    "clothing": ("clo", 0.0, 2.0),
    "metabolic rate": ("met", 0.8, 4.0),
    "relative humidity": ("rh_pct", 0.0, 100.0),
}


def ppd_from_pmv(pmv: float) -> float:
    """PPD transfer function, ISO 7730 Equation (5).

    PPD(0) = 5 %, PPD(+-0.5) = 10 %, PPD(+-1) = 26 % per the standard's
    Table 2 and Figure 1; the tests anchor those points.
    """
    return 100.0 - 95.0 * math.exp(-0.03353 * pmv**4 - 0.2179 * pmv**2)


def pmv_ppd(*, t_air_c: float, t_mrt_c: float, rh_pct: float, clo: float, met: float, v_m_s: float) -> dict:
    """PMV and PPD at one seat, port of the ISO 7730 Annex D program.

    Raises NotEvaluable outside the standard's applicability ranges so the
    caller reports a reason instead of a fabricated neutral score.
    """
    values = {
        "t_air_c": float(t_air_c),
        "t_mrt_c": float(t_mrt_c),
        "v_m_s": float(v_m_s),
        "clo": float(clo),
        "met": float(met),
        "rh_pct": float(rh_pct),
    }
    for label, (key, low, high) in APPLICABILITY.items():
        value = values[key]
        if not low <= value <= high:
            raise NotEvaluable(
                f"out of iso7730 applicability: {label} {value:g} not in [{low:g}, {high:g}]"
            )

    ta = values["t_air_c"]
    tr = values["t_mrt_c"]
    # Water vapour partial pressure [Pa]; exp() yields saturation [kPa] scaled
    # by 10 x RH% (e.g. 25 C at 50 % -> ~1583 Pa).
    pa = values["rh_pct"] * 10.0 * math.exp(16.6536 - 4030.183 / (ta + 235.0))
    if not 0.0 <= pa <= 2700.0:
        raise NotEvaluable(f"out of iso7730 applicability: water vapour pressure {pa:.0f} Pa not in [0, 2700] Pa")

    # --- Annex D program, ported line by line (scalar, no numpy/numba) ---
    icl = 0.155 * values["clo"]  # clothing insulation [m2K/W]
    m = values["met"] * MET_TO_W_M2  # metabolic rate [W/m2]
    w = 0.0  # no external mechanical work at an office seat
    mw = m - w  # internal heat production [W/m2]
    # Clothing area factor, the standard's two-branch definition.
    fcl = 1.0 + 1.29 * icl if icl <= 0.078 else 1.05 + 0.645 * icl
    hcf = 12.1 * math.sqrt(values["v_m_s"])  # forced convection coefficient
    hc = hcf
    taa = ta + 273.0
    tra = tr + 273.0
    # Annex D initial guess for the clothing surface temperature.
    t_cla = taa + (35.5 - ta) / (3.5 * (6.45 * icl + 0.1))

    p1 = icl * fcl
    p2 = p1 * 3.96
    p3 = p1 * 100.0
    p4 = p1 * taa
    p5 = (308.7 - 0.028 * mw) + p2 * (tra / 100.0) ** 4
    xn = t_cla / 100.0
    xf = t_cla / 50.0
    eps = 0.00015
    n = 0
    while abs(xn - xf) > eps:
        # Average the last two iterates, exactly as the Annex D program does.
        xf = (xf + xn) / 2.0
        # Natural convection from the averaged surface temperature; the
        # larger branch wins.
        hcn = 2.38 * abs(100.0 * xf - taa) ** 0.25
        hc = hcn if hcn > hcf else hcf
        xn = (p5 + p4 * hc - p2 * xf**4) / (100.0 + p3 * hc)
        n += 1
        if n > 150:
            raise NotEvaluable("clothing surface temperature iteration did not converge")
    tcl = 100.0 * xn - 273.0

    # Heat losses per the Annex D structure, in [W/m2].
    hl1 = 3.05e-3 * (5733.0 - 6.99 * mw - pa)  # diffusion through skin
    hl2 = 0.42 * (mw - MET_TO_W_M2) if mw > MET_TO_W_M2 else 0.0  # sweating
    hl3 = 1.7e-5 * m * (5867.0 - pa)  # latent respiration
    hl4 = 0.0014 * m * (34.0 - ta)  # dry respiration
    hl5 = 3.96e-8 * fcl * ((tcl + 273.0) ** 4 - tra**4)  # radiation
    hl6 = fcl * hc * (tcl - ta)  # convection

    pmv = (0.303 * math.exp(-0.036 * m) + 0.028) * (mw - hl1 - hl2 - hl3 - hl4 - hl5 - hl6)
    # Clause 4: the index is only for PMV between -2 and +2.
    if not -2.0 <= pmv <= 2.0:
        raise NotEvaluable(f"out of iso7730 applicability: pmv {pmv:.2f} outside -2 to +2")
    return {"pmv": pmv, "ppd": ppd_from_pmv(pmv)}


def _metric(name: str, value: float | None, *, omitted: bool, reason: str | None) -> dict:
    row: dict[str, Any] = {
        "name": name,
        "value": value,
        "unit": COMFORT_UNITS[name],
        "method": COMFORT_METHOD if not omitted else NOT_MODELED_METHOD,
        "fidelity": "l2",
        "omitted": omitted,
    }
    if reason:
        row["reason"] = reason
    return row


def omitted_comfort_metrics(reason: str) -> list[dict]:
    """All three comfort metrics omitted for one stated reason."""
    return [_metric(name, None, omitted=True, reason=reason) for name in COMFORT_METRIC_NAMES]


def comfort_metrics(seat_rows: list[dict] | None, inputs: dict | None) -> tuple[list[dict], list[dict]]:
    """(annotated seat rows, comfort metric rows).

    Complete in-range inputs annotate each seat with pmv/ppd and report
    aggregates over the evaluated seats. Missing keys keep every seat
    unannotated and omit the metrics with a reason; nothing becomes PMV=0.
    """
    rows = [dict(row) for row in seat_rows or []]
    missing = [key for key in COMFORT_INPUT_KEYS if not inputs or inputs.get(key) is None]
    if missing:
        reason = "not evaluable: missing " + ", ".join(missing) + " (comfort inputs not modeled)"
        return rows, omitted_comfort_metrics(reason)

    evaluated: list[dict] = []
    excluded: list[str] = []
    for row in rows:
        try:
            result = pmv_ppd(
                t_air_c=row["tC"],
                t_mrt_c=float(inputs["mrtC"]),
                rh_pct=float(inputs["rhPct"]),
                clo=float(inputs["clo"]),
                met=float(inputs["met"]),
                v_m_s=row["uMag"],
            )
        except NotEvaluable:
            excluded.append(str(row.get("id")))
            continue
        row["pmv"] = result["pmv"]
        row["ppd"] = result["ppd"]
        evaluated.append(row)

    if not evaluated:
        reason = (
            "not evaluable: no seat within iso7730 applicability (excluded: "
            + ", ".join(excluded)
            + ")"
        )
        return rows, omitted_comfort_metrics(reason)

    pmvs = [row["pmv"] for row in evaluated]
    ppds = [row["ppd"] for row in evaluated]
    note = None
    if excluded:
        note = (
            f"{len(excluded)} of {len(rows)} seats outside iso7730 applicability: "
            + ", ".join(excluded)
        )
    metrics = [
        _metric("seat_pmv_min", min(pmvs), omitted=False, reason=note),
        _metric("seat_pmv_max", max(pmvs), omitted=False, reason=note),
        _metric("seat_ppd_max", max(ppds), omitted=False, reason=note),
    ]
    return rows, metrics
