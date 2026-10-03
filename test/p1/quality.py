"""Control-volume mass and energy. Mixed-cup return ΔT is diagnostic only."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Any

from foam_io import (
    parse_boundary_patch,
    parse_face_list,
    parse_owner_list,
    parse_point_list,
    parse_scalar_field,
    parse_vector_field,
)
from room_input import RoomError

LOGGER = logging.getLogger("simunow.p1.quality")


def inlet_conduction_w(
    *,
    case: Path,
    time_dir: Path,
    t_supply_k: float,
    rho: float,
    cp: float,
    nu: float,
    pr: float,
) -> float:
    """Conductive exchange across the fixedValue supply plane [W, into domain].

    Why measure: a Dirichlet inlet plane under a warm stratified ceiling
    absorbs real heat from the near-inlet cells (2026-10-03: -264.2 W at the
    weak 0.1 m/s office jet; only ~-7 W under P1's 1.2 m/s jet). The CV
    energy budget must count it or a fully converged weak-jet field looks
    like a phantom 23% leak. The flux is read from the final fields, never
    assumed to be 0.
    """
    turbulence_path = case / "constant" / "turbulenceProperties"
    if not turbulence_path.is_file():
        raise RoomError("case has no turbulenceProperties")
    turbulence = turbulence_path.read_text(encoding="utf-8", errors="replace")
    if "laminar" not in turbulence:
        # alphat on the inlet faces would change the flux; do not approximate.
        raise RoomError("inlet-plane conduction accounting supports laminar alphat=0 only")

    mesh = case / "constant" / "polyMesh"
    start, count = parse_boundary_patch(
        (mesh / "boundary").read_text(encoding="utf-8", errors="replace"), "inlet"
    )
    points = parse_point_list((mesh / "points").read_text(encoding="utf-8", errors="replace"))
    faces = parse_face_list((mesh / "faces").read_text(encoding="utf-8", errors="replace"))
    owner = parse_owner_list((mesh / "owner").read_text(encoding="utf-8", errors="replace"))
    centres = parse_vector_field((time_dir / "C").read_text(encoding="utf-8", errors="replace"))
    temps = parse_scalar_field((time_dir / "T").read_text(encoding="utf-8", errors="replace"))

    if len(faces) != len(owner):
        raise RoomError(f"faces {len(faces)} but owner {len(owner)}")
    if len(centres) != len(temps):
        raise RoomError(f"C declares {len(centres)} cells but T declares {len(temps)}")
    if start + count > len(faces):
        raise RoomError("inlet startFace/nFaces exceeds the face list")

    # Laminar alphat=0, so the boundary thermal diffusivity is the laminar one.
    alpha = nu / pr
    integral = 0.0
    for face in range(start, start + count):
        labels = faces[face]
        if any(label >= len(points) for label in labels):
            raise RoomError("inlet face references a point beyond the points list")
        if owner[face] >= len(centres):
            raise RoomError("inlet face owner is beyond the cell list")
        verts = [points[label] for label in labels]
        if len(verts) != 4:
            raise RoomError("inlet face is not a quad; blockMesh faces are quads")
        # Planar quad area via diagonals; blockMesh inlet faces are planar.
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2), (x3, y3, z3) = verts
        d1 = (x2 - x0, y2 - y0, z2 - z0)
        d2 = (x3 - x1, y3 - y1, z3 - z1)
        sx = 0.5 * (d1[1] * d2[2] - d1[2] * d2[1])
        sy = 0.5 * (d1[2] * d2[0] - d1[0] * d2[2])
        sz = 0.5 * (d1[0] * d2[1] - d1[1] * d2[0])
        area = (sx * sx + sy * sy + sz * sz) ** 0.5
        if area <= 0.0:
            raise RoomError("inlet face has degenerate area")
        fx = sum(v[0] for v in verts) / len(verts)
        fy = sum(v[1] for v in verts) / len(verts)
        fz = sum(v[2] for v in verts) / len(verts)
        # Outward normal away from the owner cell centre.
        cx, cy, cz = centres[owner[face]]
        delta = abs((cx - fx) * sx / area + (cy - fy) * sy / area + (cz - fz) * sz / area)
        if delta <= 0.0:
            raise RoomError("inlet face sits in its owner cell plane")
        # OpenFOAM snGrad at a fixedValue patch: (T_boundary - T_cell)/delta.
        integral += area * (t_supply_k - temps[owner[face]]) / delta

    watts = rho * cp * alpha * integral
    LOGGER.info(
        "inlet-plane conduction %.2f W over %d faces (negative = supply plane absorbs heat)",
        watts,
        count,
    )
    return watts


def mass_energy_from_fluxes(
    *,
    vdot_in: float,
    vdot_out: float,
    t_supply_k: float,
    t_return_k: float,
    rho: float,
    cp: float,
    q_people_w: float,
    q_lights_w: float,
    q_equip_w: float,
    q_window_w: float,
    q_inlet_cond_w: float,
    mass_gate: float,
    energy_gate: float,
) -> dict[str, Any]:
    """Steady CV: enthalpy out − enthalpy in ≟ internal + window heat.

    Why not mixed-cup alone: a short-circuit return can look balanced on
    m cp (T_return − T_supply) while the occupied volume is not.
    Why q_inlet_cond_w is required: a fixedValue supply plane also exchanges
    heat conductively with the near-inlet cells. Under a weak jet that term
    is hundreds of watts (2026-10-03 office: -264.2 W at 0.1 m/s), so it is
    measured and counted; passing 0 asserts it is negligible, never guesses.
    """
    if vdot_in <= 0:
        raise ValueError("inlet volume flow must be positive")
    mass_rel = abs(vdot_in - vdot_out) / vdot_in
    h_in = rho * cp * vdot_in * t_supply_k
    h_out = rho * cp * vdot_out * t_return_k
    # Conduction into the domain relieves the return stream by the same amount:
    # h_out = h_in + q_into + q_inlet_cond_w  =>  extraction below.
    q_extracted = h_out - h_in - q_inlet_cond_w
    q_into = q_people_w + q_lights_w + q_equip_w + q_window_w
    mixed_cup_w = rho * cp * vdot_in * (t_return_k - t_supply_k)
    residual = q_extracted - q_into
    scale = max(abs(q_extracted), abs(q_into), 1.0)
    energy_rel = abs(residual) / scale
    # Mixed-cup compares against the same physical expectation the CV uses.
    expected_w = q_into + q_inlet_cond_w
    mixed_only = abs(mixed_cup_w - expected_w) / max(abs(mixed_cup_w), abs(expected_w), 1.0)
    mass_pass = mass_rel < mass_gate
    energy_pass = energy_rel < energy_gate
    LOGGER.info(
        "quality mass_rel=%.4f energy_rel=%.4f mixed_cup_only=%.4f inlet_cond=%.2fW",
        mass_rel,
        energy_rel,
        mixed_only,
        q_inlet_cond_w,
    )
    return {
        "mass": {
            "vdot_in_m3_s": vdot_in,
            "vdot_out_m3_s": vdot_out,
            "relative_error": mass_rel,
            "gate": mass_gate,
            "pass": mass_pass,
        },
        "energy": {
            "relative_error": energy_rel,
            "gate": energy_gate,
            "pass": energy_pass,
            "residual_w": residual,
            "terms_w": {
                "h_in": h_in,
                "h_out": h_out,
                "q_extracted": q_extracted,
                "q_people": q_people_w,
                "q_lights": q_lights_w,
                "q_equip": q_equip_w,
                "q_window": q_window_w,
                "q_inlet_cond": q_inlet_cond_w,
                "q_into": q_into,
            },
            "mixed_cup_w": mixed_cup_w,
            "mixed_cup_only_relative": mixed_only,
            "note": "pass uses CV enthalpy with phi-weighted patch T plus the measured supply-plane conduction; a fixedValue inlet absorbs heat under weak jets",
        },
    }
