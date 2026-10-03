"""EnergyPlus 25.2 IDF from the same Z-up room_p1.json used by OpenFOAM."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from room_input import input_hash, qty, window_area_m2, window_rects, window_total_w

LOGGER = logging.getLogger("simunow.p1.write_idf")

# ADR-012: per-person LATENT heat, listed separately from the template's
# occupantSensibleW (per-person SENSIBLE heat). Measured EnergyPlus split of
# the 70 W activity level: 57.0 W sensible + 13.0 W latent per person; the SHF
# literal in the People object is not honoured by this engine, which derives
# the split itself, so the sensible share on the L1 side is 57 W - the same
# watts the L2 field must see. Latent heat only enters the L1 q_cool account;
# it never becomes an L2 field source.
OCCUPANT_LATENT_W = 13.0


def _hhmm_ok(text: str) -> bool:
    """EnergyPlus Until fields need HH:MM. 24:00 is allowed only as an end."""
    if text == "24:00":
        return True
    parts = text.split(":")
    if len(parts) != 2 or len(parts[0]) != 2 or len(parts[1]) != 2:
        return False
    try:
        hour, minute = int(parts[0]), int(parts[1])
    except ValueError:
        return False
    return 0 <= hour <= 23 and 0 <= minute <= 59


def compact_fraction_schedule(name: str, start: str, end: str) -> str:
    """One occupied window on every day. Does not invent 8760 or annual energy."""
    if not _hhmm_ok(start) or not _hhmm_ok(end):
        raise ValueError("occupied hours must be HH:MM")
    lines = [
        "Schedule:Compact,",
        f"  {name},",
        "  Fraction,",
        "  Through: 12/31,",
        "  For: AllDays,",
    ]
    if start != "00:00":
        lines.append(f"  Until: {start}, 0.0,")
    if end == "24:00":
        lines.append("  Until: 24:00, 1.0;")
    else:
        lines.append(f"  Until: {end}, 1.0,")
        lines.append("  Until: 24:00, 0.0;")
    return "\n".join(lines)


def _schedule_names(room: dict[str, Any]) -> tuple[str, str, str]:
    """Return extra IDF text plus occupancy / HVAC schedule names.

    A missing schedule keeps AlwaysOn so P1 fixtures stay legal. A present
    schedule must not silently become AlwaysOn.
    """
    block = room.get("schedule") or {}
    occupancy = block.get("occupancy")
    hvac = block.get("hvac") or occupancy
    extra: list[str] = []
    occupancy_name = "AlwaysOn"
    hvac_name = ""
    if occupancy and _hhmm_ok(str(occupancy.get("start", ""))) and _hhmm_ok(str(occupancy.get("end", ""))):
        extra.append(compact_fraction_schedule("OccupiedHours", occupancy["start"], occupancy["end"]))
        occupancy_name = "OccupiedHours"
    if hvac and _hhmm_ok(str(hvac.get("start", ""))) and _hhmm_ok(str(hvac.get("end", ""))):
        extra.append(compact_fraction_schedule("HVACHours", hvac["start"], hvac["end"]))
        hvac_name = "HVACHours"
    extra_text = ("\n".join(extra) + "\n") if extra else ""
    return extra_text, occupancy_name, hvac_name


def l1_people_w(room: dict[str, Any]) -> float:
    """Total per-person SENSIBLE heat × count. Same watts the L2 field sees;
    latent heat is L1-only (ADR-012) and never enters the L2 volume source."""
    return qty(room["gains"]["n_people"]) * qty(room["gains"]["people_w"])


def l1_window_w(room: dict[str, Any]) -> float:
    """L1 window = UA*ΔT + SHGC×solar×A. Not the L2 q_w_m2×full-span band."""
    l1 = room["l1"]
    return qty(l1["ua_window_w_k"]) * (qty(l1["t_out_c"]) - qty(l1["t_in_c"])) + qty(l1["shgc"]) * qty(
        l1["solar_w_m2"]
    ) * qty(l1["window_area_m2"])


def l2_window_w(room: dict[str, Any]) -> float:
    """The L2 window watts, for the gains comparison table only.

    windows[] rooms (P1 fixture, P4-07): the watts the per-window patches
    actually inject (Σ q × area over rectangles). Legacy single-window
    rooms (from l1_room.py): the pre-P4-07 full-span band value stays bit
    for bit so the L1 pinned numbers do not drift.
    """
    if window_rects(room):
        return window_total_w(room)
    # Legacy L1 room: q may be absent when the draft declared no flux; that
    # is a declared 0 W, not a KeyError.
    return qty(room["window"].get("q_w_m2", {"value": 0.0})) * window_area_m2(room)


def l1_opaque_w(room: dict[str, Any]) -> float:
    l1 = room["l1"]
    return qty(l1["ua_opaque_w_k"]) * (qty(l1["t_out_c"]) - qty(l1["t_in_c"]))


def gains_table(room: dict[str, Any]) -> dict[str, Any]:
    """L1 object watts vs L2 T-equation sources. Silent agreement is not allowed."""
    people = l1_people_w(room)
    lights = qty(room["gains"]["lighting_w"])
    equip = qty(room["gains"]["equipment_w"])
    window_l1 = l1_window_w(room)
    window_l2 = l2_window_w(room)

    def row(l1_w: float, l2_w: float, note: str) -> dict[str, Any]:
        scale = max(abs(l1_w), abs(l2_w), 1.0)
        rel = abs(l1_w - l2_w) / scale
        return {"l1_w": l1_w, "l2_w": l2_w, "rel_diff": rel, "note": note}

    window_note = (
        "L1 uses UA_window*ΔT + SHGC*solar*l1.window_area; "
        "L2 uses the per-window rectangles' summed q×A (P4-07 patches). "
        "Opaque UA and infiltration exist only in L1."
    )
    return {
        "people": row(
            people,
            people,
            "per-person sensible people_w on both layers; L1 People activity = "
            f"sensible + latent {OCCUPANT_LATENT_W:g} W (latent L1-only, q_cool)",
        ),
        "lights": row(lights, lights, "same lighting_w; L1 may split radiant, L2 smears all into T"),
        "equipment": row(equip, equip, "same equipment_w; L1 may split radiant, L2 smears all into T"),
        "window": row(window_l1, window_l2, window_note),
        "opaque_ua_l1_only_w": l1_opaque_w(room),
        "infil_m3_s": qty(room["l1"]["infil_m3_s"]),
    }


def _window_xy(room: dict[str, Any]) -> tuple[float, float, float, float]:
    """East-wall window sized to l1.window_area_m2, height from the first window.

    The IDF keeps ONE window of the summed area (ADR-018 L1 side). Its height
    follows the first window rectangle: windows[] rooms (P1 fixture) read
    windows[0].z, legacy single-window rooms (l1_room.py) read window.z —
    the same value the pre-P4-07 IDF used.
    """
    ly = qty(room["size"]["y_m"])
    rects = window_rects(room)
    if rects:
        z0 = qty(rects[0]["z0_m"])
        z1 = qty(rects[0]["z1_m"])
    else:
        z0 = qty(room["window"]["z0_m"])
        z1 = qty(room["window"]["z1_m"])
    area = qty(room["l1"]["window_area_m2"])
    height = max(z1 - z0, 1e-6)
    width = min(ly - 0.2, area / height)
    y0 = 0.5 * (ly - width)
    return y0, y0 + width, z0, z1


def run_period_md(room: dict[str, Any]) -> tuple[int, int]:
    """Typical-year month/day. Missing keys stay 15 July so P1 fixtures do not drift."""
    block = room.get("l1") or {}
    if "run_month" not in block or "run_day" not in block:
        return 7, 15
    month = int(qty(block["run_month"]))
    day = int(qty(block["run_day"]))
    return month, day


def write_idf(room: dict[str, Any], dest: Path) -> Path:
    """Legal 25.2 IDF: DualSetpoint 4, empty Space Name, Ideal Loads connections."""
    dest = Path(dest)
    dest.parent.mkdir(parents=True, exist_ok=True)
    lx = qty(room["size"]["x_m"])
    ly = qty(room["size"]["y_m"])
    lz = qty(room["size"]["z_m"])
    t_in = qty(room["l1"]["t_in_c"])
    n_people = int(qty(room["gains"]["n_people"]))
    people_w = qty(room["gains"]["people_w"])
    # ADR-012: people_w is per-person SENSIBLE heat. The People activity level
    # adds the separately listed latent heat so q_cool keeps counting it. The
    # engine derives the sensible split itself (SHF literal is not honoured),
    # so 57 + 13 = 70 keeps the pre-alignment office IDF bit for bit.
    activity_w = people_w + OCCUPANT_LATENT_W
    lights_w = qty(room["gains"]["lighting_w"])
    equip_w = qty(room["gains"]["equipment_w"])
    infil = qty(room["l1"]["infil_m3_s"])
    y0, y1, z0, z1 = _window_xy(room)
    volume = lx * ly * lz
    floor_a = lx * ly
    digest = input_hash(room)
    extra_schedules, occupancy_schedule, hvac_schedule = _schedule_names(room)
    run_month, run_day = run_period_md(room)
    # Empty availability keeps Ideal Loads always on (P1 rooms with no clock window).
    hvac_availability = hvac_schedule if hvac_schedule else ""
    LOGGER.info("write IDF dest=%s hash=%s", dest.name, digest[:12])
    # Vertex order follows the 25.2 smoke IDF that already completed on this
    # engine. Space Name is the empty field after Zone Name.
    idf = f"""! SimuNow P1-04 single-zone representative day. EnergyPlus 25.2.
! input_hash {digest}
! Ideal Loads is an equivalent cooling model, not an outdoor-unit meter.
Version, 25.2;

Building, SimuNowP1Room, 0.0, Suburbs, 0.04, 0.4, FullExterior, 25, 6;
Timestep, 4;
Site:Location, HongKong, 22.3, 114.2, 8.0, 8.0;
Site:GroundTemperature:BuildingSurface, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22, 22;
! Run period only: the EPW is the weather, not a SizingPeriod:DesignDay stand-in.
SimulationControl, No, No, No, No, Yes, No, 1;
GlobalGeometryRules, UpperLeftCorner, CounterClockWise, World;

! Begin/End Year slots stay empty (EnergyPlus 9.6+).
RunPeriod, WeatherDay, {run_month}, {run_day}, , {run_month}, {run_day}, , Thursday, Yes, Yes, No, Yes, Yes;

ScheduleTypeLimits, Fraction, 0.0, 1.0, CONTINUOUS;
ScheduleTypeLimits, Temperature, , , CONTINUOUS;
ScheduleTypeLimits, ActivityLevel, 0, 1000, CONTINUOUS;
ScheduleTypeLimits, ControlType, 0, 4, DISCRETE;
Schedule:Constant, AlwaysOn, Fraction, 1.0;
Schedule:Constant, HeatSet, Temperature, {t_in};
Schedule:Constant, CoolSet, Temperature, {t_in};
Schedule:Constant, Activity, ActivityLevel, {activity_w:.6g};
! Control type 4 = DualSetpoint. An occupancy fraction is not valid here.
Schedule:Constant, DualControl, ControlType, 4;
{extra_schedules}

Material, Concrete, Rough, 0.15, 1.4, 2200, 880, 0.9, 0.65, 0.65;
Material, Gypsum, MediumSmooth, 0.012, 0.16, 800, 1090, 0.9, 0.6, 0.6;
WindowMaterial:SimpleGlazingSystem, SimpleGlass, 2.7, 0.65, 0.7;
Construction, WallConst, Concrete, Gypsum;
Construction, FloorConst, Concrete;
Construction, RoofConst, Concrete;
Construction, WinConst, SimpleGlass;

Zone, Room, 0, 0, 0, 0, 1, {lz}, {volume}, {floor_a};

BuildingSurface:Detailed, Floor, Floor, FloorConst, Room, , Ground, , NoSun, NoWind, 0.5, 4,  0,0,0,  0,{ly},0,  {lx},{ly},0,  {lx},0,0;
BuildingSurface:Detailed, Ceiling, Roof, RoofConst, Room, , Outdoors, , SunExposed, WindExposed, 0.5, 4,  0,0,{lz},  {lx},0,{lz},  {lx},{ly},{lz},  0,{ly},{lz};
BuildingSurface:Detailed, WallS, Wall, WallConst, Room, , Outdoors, , SunExposed, WindExposed, 0.5, 4,  0,0,0,  0,0,{lz},  {lx},0,{lz},  {lx},0,0;
BuildingSurface:Detailed, WallN, Wall, WallConst, Room, , Outdoors, , SunExposed, WindExposed, 0.5, 4,  0,{ly},0,  {lx},{ly},0,  {lx},{ly},{lz},  0,{ly},{lz};
BuildingSurface:Detailed, WallE, Wall, WallConst, Room, , Outdoors, , SunExposed, WindExposed, 0.5, 4,  {lx},0,0,  {lx},0,{lz},  {lx},{ly},{lz},  {lx},{ly},0;
BuildingSurface:Detailed, WallW, Wall, WallConst, Room, , Outdoors, , SunExposed, WindExposed, 0.5, 4,  0,0,0,  0,{ly},0,  0,{ly},{lz},  0,0,{lz};
FenestrationSurface:Detailed, EastWin, Window, WinConst, WallE, , , , , 4,  {lx},{y0},{z0},  {lx},{y0},{z1},  {lx},{y1},{z1},  {lx},{y1},{z0};

! ADR-012: activity 57 sensible + 13 latent per person. The SHF literal 0.3 is
! not honoured by this engine (it derives the split itself); kept for legibility.
People, Occupants, Room, {occupancy_schedule}, People, {n_people}, , , 0.3, AUTOCALCULATE, Activity;
Lights, RoomLights, Room, {occupancy_schedule}, LightingLevel, {lights_w}, , , 0, 0.2, 0.2, 0, GeneralLights;
ElectricEquipment, PlugLoads, Room, {occupancy_schedule}, EquipmentLevel, {equip_w}, , , 0, 0.5, 0;
ZoneInfiltration:DesignFlowRate, Infil, Room, AlwaysOn, Flow/Zone, {infil}, , , , 1, 0, 0, 0;

ZoneControl:Thermostat, RoomTstat, Room, DualControl, ThermostatSetpoint:DualSetpoint, RoomDual;
ThermostatSetpoint:DualSetpoint, RoomDual, HeatSet, CoolSet;

ZoneHVAC:EquipmentConnections, Room, RoomEq, RoomSupply, , RoomAir, RoomReturn;
ZoneHVAC:EquipmentList, RoomEq, SequentialLoad, ZoneHVAC:IdealLoadsAirSystem, IdealAC, 1, 1, , ;
ZoneHVAC:IdealLoadsAirSystem,
  IdealAC, {hvac_availability}, RoomSupply, , ,
  50, 13, 0.0156, 0.0077,
  NoLimit, , ,
  NoLimit, , ,
  , ,
  ConstantSensibleHeatRatio, 0.7, None, ,
  , None, NoEconomizer, None, 0.70, 0.65;

Output:Variable, *, Zone Mean Air Temperature, Hourly;
Output:Variable, *, Zone Ideal Loads Supply Air Total Cooling Energy, Hourly;
Output:Variable, *, Zone Ideal Loads Supply Air Total Cooling Rate, Hourly;
Output:Variable, *, Surface Inside Face Temperature, Hourly;
Output:Variable, *, Zone Windows Total Heat Gain Rate, Hourly;
Output:Variable, *, Zone Windows Total Heat Loss Rate, Hourly;
Output:Variable, *, Surface Inside Face Conduction Heat Transfer Rate, Hourly;
Output:VariableDictionary, Regular;
"""
    dest.write_text(idf, encoding="utf-8")
    return dest
