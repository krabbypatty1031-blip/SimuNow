"""Map a P2 ProjectDraft onto the P1 room JSON that write_openfoam_room understands.

Does not invent envelope UA, wall temperatures, or quality.pass.
Furniture boxes reach the L2 case as blocked cells since 2026-10-04; the
kind (desk/chair/cabinet/screen) is a display label only and never changes
the solver input.
"""

from __future__ import annotations

from copy import deepcopy

from simunow_worker.models.project import patch_area_m2


def l1_metric_w(l1: dict | None, name: str) -> float | None:
    """Read a non-omitted watt metric. A reported 0 W is kept; missing stays None."""
    if not l1:
        return None
    for item in l1.get("metrics") or []:
        if item.get("name") != name or item.get("omitted"):
            continue
        value = item.get("value")
        if value is None:
            return None
        return float(value)
    return None


def apply_l1_envelope(draft: dict, l1: dict | None) -> dict:
    """Copy the draft and replace window fluxes so ΣqA equals L1 window heat.

    Does not invent weather heat when L1 omitted the metric. Opaque watts
    are attached as `_opaqueHeatW` for the case writer only.
    """
    if not l1:
        return draft
    window_w = l1_metric_w(l1, "window_heat_w")
    opaque_w = l1_metric_w(l1, "opaque_heat_w")
    if window_w is None and opaque_w is None:
        return draft
    out = deepcopy(draft)
    geometry = out.get("geometry") or {}
    windows = [item for item in geometry.get("openings", []) if item.get("kind") == "window"]
    area = sum(patch_area_m2(item) for item in windows)
    if window_w is not None and area > 0:
        flux = window_w / area
        for item in windows:
            item["heatFluxWm2"] = {
                "value": flux,
                "unit": "W/m2",
                "source": "l1_energyplus",
            }
    if opaque_w is not None:
        out["_opaqueHeatW"] = opaque_w
    return out

_WALL_X = {
    "xMin": lambda size: 0.0,
    "xMax": lambda size: size[0],
    "yMin": lambda size: 0.0,
    "yMax": lambda size: size[1],
}


def _qty(node: dict, source: str = "project") -> dict:
    return {
        "value": node["value"],
        "unit": node.get("unit", "1"),
        "source": node.get("source", source),
    }


def _assumed(value: float, unit: str) -> dict:
    return {"value": value, "unit": unit, "source": "assumed"}


def _ladder(value: float, unit: str) -> dict:
    """A P4-07B ladder pick, adopted only after all five gates passed (ADR-020)."""
    return {"value": value, "unit": unit, "source": "p4_07b_ladder"}


def _wall_span(wall: str, size: tuple[float, float, float]) -> float:
    """Length of the wall a patch sits on. xMin/xMax run along y; yMin/yMax along x."""
    return size[1] if wall in ("xMin", "xMax") else size[0]


def _band_scale(patch: dict, wall: str, size: tuple[float, float, float]) -> float:
    """Patch width / full wall span.

    The P1 case writer still makes the SUPPLY band full-wall. Scaling the
    velocity by this ratio preserves the project's supply m3/s; the geometry
    simplification is recorded in assumptions instead of silently changing
    the physics. Windows no longer use this: each window patch keeps its own
    span since P4-07.
    """
    span = _wall_span(wall, size)
    width = patch["s1"]["value"] - patch["s0"]["value"]
    return width / span


def _windows(geometry: dict) -> list[dict]:
    """All window openings, in draft order. Doors are not glazed and stay out."""
    return [item for item in geometry.get("openings", []) if item.get("kind") == "window"]


def _window_area_m2(windows: list[dict]) -> float:
    """Total glazed area over all windows."""
    return sum(patch_area_m2(item) for item in windows)


def _obstacles(geometry: dict) -> list[dict]:
    """Validated furniture AABBs in contract metres (2026-10-04).

    The App's placement rules already refuse boxes that leave the room or
    overlap furniture/seats/terminal bands/windows; this mapper still
    validates the room bounds so a hand-edited or migrated project is an
    honest failed task, never a case with furniture hanging off the mesh.
    """
    size = (
        geometry["sizeX"]["value"],
        geometry["sizeY"]["value"],
        geometry["sizeZ"]["value"],
    )
    boxes = []
    for index, item in enumerate(geometry.get("obstacles") or []):
        origin = item.get("origin") or {}
        box_size = item.get("size") or {}
        x0, y0, z0 = float(origin["x"]), float(origin["y"]), float(origin["z"])
        sx, sy, sz = float(box_size["x"]), float(box_size["y"]), float(box_size["z"])
        x1, y1, z1 = x0 + sx, y0 + sy, z0 + sz
        if not (0 <= x0 < x1 <= size[0] + 1e-9 and 0 <= y0 < y1 <= size[1] + 1e-9 and 0 <= z0 < z1 <= size[2] + 1e-9):
            raise ValueError(
                f"obstacle {item.get('id', index)} leaves the room box "
                f"0..{size[0]:g} x 0..{size[1]:g} x 0..{size[2]:g} m"
            )
        boxes.append(
            {
                "id": str(item.get("id", f"F{index + 1}")),
                "kind": str(item.get("kind", "desk")),
                "x0": x0,
                "y0": y0,
                "z0": z0,
                "x1": x1,
                "y1": y1,
                "z1": z1,
            }
        )
    return boxes


# Walls a window may sit on. xMin/xMax run along y; yMin/yMax along x.
_WINDOW_WALLS = ("xMin", "xMax", "yMin", "yMax")
# Rectangles closer than this are treated as intersecting / out of bounds.
_RECT_EPS = 1e-9


def _rects_overlap(a: dict, b: dict) -> bool:
    """Two same-wall rectangles claim the same mesh faces only if both intervals overlap."""
    return (
        a["s0"] < b["s1"] - _RECT_EPS
        and b["s0"] < a["s1"] - _RECT_EPS
        and a["z0"] < b["z1"] - _RECT_EPS
        and b["z0"] < a["z1"] - _RECT_EPS
    )


def _merge_window_rects(rects: list[dict]) -> list[dict]:
    """Merge same-wall intersecting rectangles until pairwise disjoint.

    Why merge instead of reject: the editor allows any placement, and a
    failed task over overlapping windows would turn a legal draft into an
    error. One patch region can carry one gradient, so the merged bounding
    box carries the SUMMED watts (q = ΣW / bbox area): total W is conserved
    exactly, never silently lost or double-counted. The merge is disclosed
    in assumptions.
    """
    rects = list(rects)
    changed = True
    while changed:
        changed = False
        for i in range(len(rects)):
            for j in range(i + 1, len(rects)):
                if rects[i]["wall"] != rects[j]["wall"] or not _rects_overlap(rects[i], rects[j]):
                    continue
                a, b = rects[i], rects[j]
                watts = a["w"] + b["w"]
                s0, s1 = min(a["s0"], b["s0"]), max(a["s1"], b["s1"])
                z0, z1 = min(a["z0"], b["z0"]), max(a["z1"], b["z1"])
                rects[i : j + 1] = [
                    {
                        "wall": a["wall"],
                        "s0": s0,
                        "s1": s1,
                        "z0": z0,
                        "z1": z1,
                        # Area-weighted conservation: q x bbox area == ΣW.
                        "q": watts / ((s1 - s0) * (z1 - z0)),
                        "w": watts,
                        "merged": True,
                    }
                ]
                changed = True
                break
            if changed:
                break
    return rects


def _window_rects(windows: list[dict], size: tuple[float, float, float], hvac: dict) -> list[dict]:
    """Validated per-window rectangles for the case writer.

    Raises ValueError (surfaced as a failed task with the reason) when a
    window leaves its wall / the room, or claims inlet/outlet faces on xMin.
    """
    rects = []
    for item in windows:
        wall = item.get("wall")
        if wall not in _WINDOW_WALLS:
            raise ValueError(f"window {item.get('id', '?')} wall {wall!r} is not one of xMin/xMax/yMin/yMax")
        s0, s1 = float(item["s0"]["value"]), float(item["s1"]["value"])
        z0, z1 = float(item["z0"]["value"]), float(item["z1"]["value"])
        if s0 >= s1 - _RECT_EPS or z0 >= z1 - _RECT_EPS:
            raise ValueError(f"window {item.get('id', '?')} has an empty rectangle")
        # No declared flux is a declared 0 W, never an invented one.
        flux = item.get("heatFluxWm2")
        q = float(flux["value"]) if flux else 0.0
        area = (s1 - s0) * (z1 - z0)
        rects.append({"wall": wall, "s0": s0, "s1": s1, "z0": z0, "z1": z1, "q": q, "w": q * area})
    rects = _merge_window_rects(rects)
    for rect in rects:
        span = _wall_span(rect["wall"], size)
        if rect["s0"] < -_RECT_EPS or rect["s1"] > span + _RECT_EPS:
            raise ValueError(f"window on {rect['wall']} exceeds the wall span 0..{span:g} m")
        if rect["z0"] < -_RECT_EPS or rect["z1"] > size[2] + _RECT_EPS:
            raise ValueError(f"window on {rect['wall']} exceeds the room height 0..{size[2]:g} m")
        if rect["wall"] == "xMin":
            # The supply/return bands own the full xMin span at their heights;
            # a window there would lose its watts to the inlet/outlet faces.
            for band, terminal in (("supply", hvac["supply"]), ("return", hvac["returnTerminal"])):
                bz0, bz1 = float(terminal["z0"]["value"]), float(terminal["z1"]["value"])
                if rect["z0"] < bz1 - _RECT_EPS and bz0 < rect["z1"] - _RECT_EPS:
                    raise ValueError(
                        f"window on xMin overlaps the {band} band z {bz0:g}..{bz1:g} m; move the window off the grille"
                    )
    return rects



def project_to_l2_room(draft: dict, l1: dict | None = None) -> dict:
    """Build a P1-shaped L2 room. Supply T is the coil, not the zone setpoint."""
    draft = apply_l1_envelope(draft, l1)
    geometry = draft.get("geometry")
    occupancy = draft.get("occupancy")
    hvac = draft.get("hvac")
    if not geometry or not occupancy or not hvac:
        raise ValueError("incompleteProject")
    windows = _windows(geometry)
    if not windows:
        raise ValueError("project has no window opening")
    size = (
        geometry["sizeX"]["value"],
        geometry["sizeY"]["value"],
        geometry["sizeZ"]["value"],
    )
    # Every window keeps its own wall, span and height since P4-07; the
    # case writer meshes each rectangle as its own patch. Draft-level sums
    # stay the L1-comparable totals (area Σ before any merge). The emitted
    # per-window watts sum to the same total W through any merge.
    window_rects = _window_rects(windows, size, hvac)
    window_area = _window_area_m2(windows)
    obstacles = _obstacles(geometry)
    seats = occupancy.get("seats", [])
    seat_z = seats[0]["position"]["z"] if seats else 1.1
    outdoor = hvac["outdoorAirM3s"]["value"]
    supply_flow = hvac["supplyAirflowM3s"]["value"]
    supply_wall = hvac["supply"]["wall"]
    # Supply stays the one full-wall band: the writer still places it on the
    # x=0 wall as a full-span height band, so velocity is scaled to preserve
    # the project's declared supply m3/s.
    supply_scale = _band_scale(hvac["supply"], supply_wall, size)
    return {
        "name": draft.get("name", "room"),
        "kind": "room",
        "coordinates": {
            "system": "metre_right_handed_z_up",
            "foam_up_axis": "Y",
            "gravity_contract_m_s2": [0, 0, -9.81],
            "gravity_foam_m_s2": [0, -9.81, 0],
        },
        "assumptions": [
            # Furnished rooms carry the blocked-cell disclosure instead of the
            # old omission; empty rooms keep the omission (nothing to block).
            *( ["furniture boxes enter the L2 case as blocked cells (boxToCell/subsetMesh)"] if obstacles
                else ["omitted: furniture_boxes"] ),
            *( ["furniture kind (desk/chair/cabinet/screen) is a display label; the solver sees one blocked box per piece"] if obstacles
                else ["P1 first-version L2 case has no furniture boxes"] ),
            *( [
                "furniture surfaces are solid and adiabatic; thermal mass is not modeled",
                "furniture blocks whole cells selected by cell centre; box edges snap to the mesh",
            ] if obstacles else [] ),
            *(
                ["opaque envelope heat is the EnergyPlus day mean, spread on the walls patch"]
                if draft.get("_opaqueHeatW") is not None
                else ["omitted: envelope_u_value"]
            ),
            *(
                ["window flux is the EnergyPlus day mean, spread by glazed area"]
                if l1_metric_w(l1, "window_heat_w") is not None
                else ["window flux is the draft assumption until a current L1 result exists"]
            ),
            "wall temperatures are not invented from UA",
            "supply band spans the full wall; velocity scaled to preserve project supply m3/s",
            "each window enters at its own wall, span and height; total window W is the sum over windows",
            "same-wall overlapping windows are merged into one rectangle; total window W is conserved",
            "mesh 24x20x18 and nu 0.003 m2/s are P4-07B ladder picks; all five gates passed (ADR-020)",
            "nu is a turbulence-equivalent effective viscosity, ~200x molecular air viscosity; the laminar solver is unchanged",
        ],
        "size": {
            "x_m": _qty(geometry["sizeX"]),
            "y_m": _qty(geometry["sizeY"]),
            "z_m": _qty(geometry["sizeZ"]),
        },
        "mesh": {
            # P4-07B ladder: 24x20x18 passed all five gates (checkMesh, solver
            # end, monitors, mass, energy) and put the slice max 0.12 m from
            # the window plane; 61 s solve stays inside the App 900 s budget.
            "nx": _ladder(24, "1"),
            "n_span": _ladder(20, "1"),
            "n_height": _ladder(18, "1"),
        },
        "air": {
            "rho": _assumed(1.2, "kg/m3"),
            "cp": _assumed(1006.0, "J/(kg.K)"),
            # P4-07B ladder stop at 0.003: all gates passed on both meshes;
            # 0.0015 also passed but flipped the near/far window seat delta
            # between meshes (-0.12 K vs +0.00 K), so seat numbers there are
            # mesh-sensitive and stay unpinned.
            "nu": _ladder(0.003, "m2/s"),
            "pr": _assumed(0.71, "1"),
            "beta": _assumed(0.0033, "1/K"),
            "t_ref_c": _qty(hvac["setpointC"]),
        },
        "supply": {
            "t_c": _qty(hvac["supplyTemperatureC"]),
            # Band velocity preserves the project's declared supply airflow.
            "u_m_s": {
                "value": hvac["supplySpeedMs"]["value"] * supply_scale,
                "unit": "m/s",
                "source": "project",
            },
            "x_m": {"value": _WALL_X[supply_wall](size), "unit": "m", "source": "project"},
            "z0_m": _qty(hvac["supply"]["z0"]),
            "z1_m": _qty(hvac["supply"]["z1"]),
        },
        "return": {
            "x_m": {"value": _WALL_X[hvac["returnTerminal"]["wall"]](size), "unit": "m", "source": "project"},
            "z0_m": _qty(hvac["returnTerminal"]["z0"]),
            "z1_m": _qty(hvac["returnTerminal"]["z1"]),
        },
        # One entry per (merged) window rectangle: the writer meshes each as
        # its own patch with its own fixedGradient. No-flux windows carry a
        # declared 0 W — a real statement, not an invented one.
        "windows": [
            {
                "wall": rect["wall"],
                "s0_m": {"value": rect["s0"], "unit": "m", "source": "project"},
                "s1_m": {"value": rect["s1"], "unit": "m", "source": "project"},
                "z0_m": {"value": rect["z0"], "unit": "m", "source": "project"},
                "z1_m": {"value": rect["z1"], "unit": "m", "source": "project"},
                # Per-rectangle flux: this patch injects q x its own area.
                # A merged rectangle carries ΣW / bbox area so W is conserved.
                "q_w_m2": {
                    "value": rect["q"],
                    "unit": "W/m2",
                    "source": "l1_energyplus" if l1_metric_w(l1, "window_heat_w") is not None else "project",
                },
                "area_m2": {
                    "value": (rect["s1"] - rect["s0"]) * (rect["z1"] - rect["z0"]),
                    "unit": "m2",
                    "source": "project",
                },
            }
            for rect in window_rects
        ],
        # One entry per furniture box in contract Z-up metres: the case writer
        # turns each AABB into blocked mesh cells. `kind` rides along for
        # disclosure; it never changes the solver input.
        "obstacles": [
            {
                "id": box["id"],
                "kind": box["kind"],
                "x0_m": {"value": box["x0"], "unit": "m", "source": "project"},
                "y0_m": {"value": box["y0"], "unit": "m", "source": "project"},
                "z0_m": {"value": box["z0"], "unit": "m", "source": "project"},
                "x1_m": {"value": box["x1"], "unit": "m", "source": "project"},
                "y1_m": {"value": box["y1"], "unit": "m", "source": "project"},
                "z1_m": {"value": box["z1"], "unit": "m", "source": "project"},
            }
            for box in obstacles
        ],
        "gains": {
            "n_people": _qty(occupancy["occupantCount"]),
            "people_w": _qty(occupancy["occupantSensibleW"]),
            "lighting_w": _qty(occupancy["lightingW"]),
            "equipment_w": _qty(occupancy["equipmentW"]),
        },
        "seats": [
            {
                "id": seat["id"],
                "x_m": seat["position"]["x"],
                "y_m": seat["position"]["y"],
                "z_m": seat["position"]["z"],
                "source": seat.get("source", "project"),
            }
            for seat in seats
        ],
        "seat_height_m": {"value": seat_z, "unit": "m", "source": "project"},
        # Initial field guess only. Not a solved air temperature.
        "t_init_c": {
            "value": hvac["setpointC"]["value"],
            "unit": "C",
            "source": "assumed",
        },
        "setpoint_c": _qty(hvac["setpointC"]),
        "ventilation": {
            "outdoor_m3_s": _qty(hvac["outdoorAirM3s"]),
            "recirculated_m3_s": {
                "value": max(0.0, supply_flow - outdoor),
                "unit": "m3/s",
                "source": "project",
            },
        },
        # Summed glazed area over all windows, matching the L1 window area.
        "window_area_m2": {"value": window_area, "unit": "m2", "source": "project"},
        **(
            {
                "opaque_heat_w": {
                    "value": float(draft["_opaqueHeatW"]),
                    "unit": "W",
                    "source": "l1_energyplus",
                }
            }
            if draft.get("_opaqueHeatW") is not None
            else {}
        ),
        "solver": {
            "end_time": _assumed(4000, "1"),
            "monitor_n": _assumed(20, "1"),
            "monitor_dt_k": _assumed(0.05, "K"),
            "monitor_du_m_s": _assumed(0.02, "m/s"),
            "rerun_dt_k": _assumed(0.2, "K"),
        },
        "quality_gates": {
            "mass_rel": _assumed(0.01, "1"),
            "energy_rel": _assumed(0.05, "1"),
        },
    }
