"""Write an OpenFOAM v2512 room case from Z-up room_p1.json."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from room_input import (
    foam_xyz,
    inlet_area_m2,
    input_hash,
    internal_gain_w,
    qty,
    room_box,
    window_area_m2,
)

LOGGER = logging.getLogger("simunow.p1.write_of")


def _header(cls: str, obj: str) -> str:
    return f"FoamFile {{ version 2.0; format ascii; class {cls}; object {obj}; }}\n"


def _write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not text.endswith("\n"):
        text += "\n"
    path.write_text(text, encoding="utf-8")


def _unique_heights(*values: float) -> list[float]:
    ordered: list[float] = []
    for value in sorted(values):
        if not ordered or abs(value - ordered[-1]) > 1e-9:
            ordered.append(value)
    return ordered


def _allocate_cells(lengths: list[float], target: int, min_each: int = 2) -> list[int]:
    """Keep thin inlet/outlet bands at least two cells so checkMesh stays usable."""
    safe = [max(length, 1e-9) for length in lengths]
    total = sum(safe)
    counts = [max(min_each, int(round(target * length / total))) for length in safe]
    return counts


def _band_name(mid: float, z0: float, z1: float) -> bool:
    return z0 - 1e-9 <= mid <= z1 + 1e-9


def write_openfoam_room(room: dict[str, Any], dest: Path) -> Path:
    """Y-up OpenFOAM case. Sampling must convert back with contract_xyz."""
    dest = Path(dest)
    for sub in ("0", "constant", "system"):
        (dest / sub).mkdir(parents=True, exist_ok=True)

    lx, span, height = room_box(room)
    nx = int(qty(room["mesh"]["nx"]))
    n_span = int(qty(room["mesh"]["n_span"]))
    n_height = int(qty(room["mesh"]["n_height"]))
    supply_z0, supply_z1 = qty(room["supply"]["z0_m"]), qty(room["supply"]["z1_m"])
    return_z0, return_z1 = qty(room["return"]["z0_m"]), qty(room["return"]["z1_m"])
    win_z0, win_z1 = qty(room["window"]["z0_m"]), qty(room["window"]["z1_m"])
    cuts = _unique_heights(0.0, win_z0, return_z0, return_z1, win_z1, supply_z0, supply_z1, height)
    lengths = [cuts[i + 1] - cuts[i] for i in range(len(cuts) - 1)]
    nys = _allocate_cells(lengths, n_height)
    u_in = qty(room["supply"]["u_m_s"])
    t_supply = qty(room["supply"]["t_c"]) + 273.15
    t_init = qty(room["t_init_c"]) + 273.15
    t_ref = qty(room["air"]["t_ref_c"]) + 273.15
    nu = qty(room["air"]["nu"])
    pr = qty(room["air"]["pr"])
    rho = qty(room["air"]["rho"])
    cp = qty(room["air"]["cp"])
    q_w = qty(room["window"]["q_w_m2"])
    # Fourier: q_into = -k * dT/dn_out. On this mesh a negative fixedGradient
    # produced min(T)=14.8°C (colder than 16°C supply) and Q_extracted≈Q_people-Q_window,
    # i.e. the patch acted as a sink. Positive gradient puts heat into the fluid.
    kappa = rho * cp * (nu / pr)
    window_gradient = q_w / kappa
    volume = lx * span * height
    su_t = internal_gain_w(room) / (rho * cp * volume)
    end_time = int(qty(room["solver"]["end_time"]))
    seat_h = qty(room["seat_height_m"])
    far = max(room["seats"], key=lambda seat: float(seat["x_m"]))
    inlet_pt = foam_xyz(0.05, span * 0.5, 0.5 * (supply_z0 + supply_z1))
    outlet_pt = foam_xyz(0.05, span * 0.5, 0.5 * (return_z0 + return_z1))
    far_pt = foam_xyz(float(far["x_m"]), float(far["y_m"]), float(far["z_m"]))

    LOGGER.info("write OF room case dest=%s nx=%s n_span=%s bands=%s", dest.name, nx, n_span, nys)

    vertices: list[str] = []
    for y in cuts:
        vertices.extend(
            [
                f"    (0 {y:.6f} 0)",
                f"    ({lx:.6f} {y:.6f} 0)",
                f"    ({lx:.6f} {y:.6f} {span:.6f})",
                f"    (0 {y:.6f} {span:.6f})",
            ]
        )
    blocks: list[str] = []
    faces: dict[str, list[str]] = {
        "inlet": [],
        "outlet": [],
        "window": [],
        "walls": [],
        "frontAndBack": [],
    }
    xmin_of: list[str] = []
    for block, ny in enumerate(nys):
        bot = 4 * block
        top = 4 * (block + 1)
        ids = [bot + 0, bot + 1, top + 1, top + 0, bot + 3, bot + 2, top + 2, top + 3]
        blocks.append(f"    hex ({' '.join(str(i) for i in ids)}) ({nx} {ny} {n_span}) simpleGrading (1 1 1)")
        xmin = f"({ids[0]} {ids[4]} {ids[7]} {ids[3]})"
        xmax = f"({ids[1]} {ids[2]} {ids[6]} {ids[5]})"
        ymin = f"({ids[0]} {ids[1]} {ids[5]} {ids[4]})"
        ymax = f"({ids[3]} {ids[7]} {ids[6]} {ids[2]})"
        zmin = f"({ids[0]} {ids[3]} {ids[2]} {ids[1]})"
        zmax = f"({ids[4]} {ids[5]} {ids[6]} {ids[7]})"
        mid = 0.5 * (cuts[block] + cuts[block + 1])
        if _band_name(mid, supply_z0, supply_z1):
            faces["inlet"].append(xmin)
            xmin_of.append("inlet")
        elif _band_name(mid, return_z0, return_z1):
            faces["outlet"].append(xmin)
            xmin_of.append("outlet")
        else:
            faces["walls"].append(xmin)
            xmin_of.append("walls")
        if _band_name(mid, win_z0, win_z1):
            faces["window"].append(xmax)
        else:
            faces["walls"].append(xmax)
        if block == 0:
            faces["walls"].append(ymin)
        if block == len(nys) - 1:
            faces["walls"].append(ymax)
        faces["frontAndBack"].extend([zmin, zmax])

    if not faces["inlet"] or not faces["outlet"] or not faces["window"]:
        raise RuntimeError(f"missing patches xmin_of={xmin_of}")

    def patch(name: str, kind: str) -> str:
        return f"    {name} {{ type {kind}; faces ( {' '.join(faces[name])} ); }}"

    _write(
        dest / "system" / "blockMeshDict",
        _header("dictionary", "blockMeshDict")
        + "convertToMeters 1;\nvertices\n(\n"
        + "\n".join(vertices)
        + "\n);\nblocks\n(\n"
        + "\n".join(blocks)
        + "\n);\nedges ();\nboundary\n(\n"
        + "\n".join(
            [
                patch("inlet", "patch"),
                patch("outlet", "patch"),
                patch("window", "wall"),
                patch("walls", "wall"),
                patch("frontAndBack", "wall"),
            ]
        )
        + "\n);\nmergePatchPairs ();\n",
    )
    _write(
        dest / "system" / "controlDict",
        _header("dictionary", "controlDict")
        + f"""application     buoyantBoussinesqSimpleFoam;
startFrom       startTime;
startTime       0;
stopAt          endTime;
endTime         {end_time};
deltaT          1;
writeControl    timeStep;
writeInterval   {end_time};
purgeWrite      1;
writeFormat     ascii;
writePrecision  8;
runTimeModifiable false;
functions
{{
    probes
    {{
        type            probes;
        libs            (sampling);
        writeControl    timeStep;
        writeInterval   5;
        fields          (T U);
        probeLocations
        (
            ({inlet_pt[0]:.4f} {inlet_pt[1]:.4f} {inlet_pt[2]:.4f})
            ({outlet_pt[0]:.4f} {outlet_pt[1]:.4f} {outlet_pt[2]:.4f})
            ({far_pt[0]:.4f} {far_pt[1]:.4f} {far_pt[2]:.4f})
        );
    }}
    inletFlow
    {{
        type            surfaceFieldValue;
        libs            (fieldFunctionObjects);
        writeControl    timeStep;
        writeInterval   50;
        writeFields     false;
        regionType      patch;
        name            inlet;
        operation       sum;
        fields          (phi);
    }}
    outletFlow
    {{
        type            surfaceFieldValue;
        libs            (fieldFunctionObjects);
        writeControl    timeStep;
        writeInterval   50;
        writeFields     false;
        regionType      patch;
        name            outlet;
        operation       sum;
        fields          (phi);
    }}
    inletT
    {{
        type            surfaceFieldValue;
        libs            (fieldFunctionObjects);
        writeControl    timeStep;
        writeInterval   50;
        writeFields     false;
        regionType      patch;
        name            inlet;
        operation       weightedAverage;
        weightField     phi;
        fields          (T);
    }}
    outletT
    {{
        type            surfaceFieldValue;
        libs            (fieldFunctionObjects);
        writeControl    timeStep;
        writeInterval   50;
        writeFields     false;
        regionType      patch;
        name            outlet;
        operation       weightedAverage;
        weightField     phi;
        fields          (T);
    }}
    seatSlice
    {{
        type            surfaces;
        libs            (sampling);
        writeControl    writeTime;
        surfaceFormat   vtk;
        interpolationScheme cellPoint;
        fields          (T U);
        surfaces
        {{
            seatHeight
            {{
                type            cuttingPlane;
                planeType       pointAndNormal;
                pointAndNormalDict
                {{
                    point   (0 {seat_h:.4f} 0);
                    normal  (0 1 0);
                }}
                interpolate     true;
            }}
        }}
    }}
}}
""",
    )
    _write(
        dest / "system" / "fvSchemes",
        _header("dictionary", "fvSchemes")
        + """ddtSchemes { default steadyState; }
gradSchemes { default Gauss linear; }
divSchemes
{
    default none;
    div(phi,U) bounded Gauss upwind;
    // Unbounded upwind for T: the bounded limiter was dropping enthalpy so
    // the CV residual could not close even after fvOptions applied.
    div(phi,T) Gauss upwind;
    div((nuEff*dev2(T(grad(U))))) Gauss linear;
}
laplacianSchemes { default Gauss linear corrected; }
interpolationSchemes { default linear; }
snGradSchemes { default corrected; }
""",
    )
    _write(
        dest / "system" / "fvSolution",
        _header("dictionary", "fvSolution")
        + """solvers
{
    p_rgh { solver PCG; preconditioner DIC; tolerance 1e-07; relTol 0; }
    "(U|T)" { solver PBiCGStab; preconditioner DILU; tolerance 1e-08; relTol 0; }
}
SIMPLE
{
    nNonOrthogonalCorrectors 0;
    // T 1e-4 met while enthalpy was still ~70% open; probes can look flat first.
    residualControl { p_rgh 1e-4; Ux 1e-4; Uy 1e-4; Uz 1e-4; T 1e-6; }
    pRefCell 0;
    pRefValue 0;
}
relaxationFactors
{
    fields { p_rgh 0.7; }
    equations { U 0.3; T 0.5; }
}
""",
    )
    _write(
        dest / "constant" / "g",
        _header("uniformDimensionedVectorField", "g")
        + """dimensions [0 1 -2 0 0 0 0];
value (0 -9.81 0);
""",
    )
    props = f"""viscosityModel  constant;
nu              [0 2 -1 0 0 0 0] {nu:.16g};
beta            [0 0 0 -1 0 0 0] {qty(room["air"]["beta"]):.16g};
TRef            [0 0 0 1 0 0 0] {t_ref:.16g};
Pr              [0 0 0 0 0 0 0] {pr:.16g};
Prt             [0 0 0 0 0 0 0] 0.85;
"""
    _write(dest / "constant" / "physicalProperties", _header("dictionary", "physicalProperties") + props)
    _write(
        dest / "constant" / "transportProperties",
        _header("dictionary", "transportProperties") + "transportModel Newtonian;\n" + props,
    )
    laminar = _header("dictionary", "momentumTransport") + "simulationType laminar;\n"
    _write(dest / "constant" / "momentumTransport", laminar)
    _write(dest / "constant" / "turbulenceProperties", _header("dictionary", "turbulenceProperties") + "simulationType laminar;\n")
    # v2512 sources tuple is (Su, Sp) for field T. The explicit/implicit
    # sub-dict also parses, but the header documents the tuple as the
    # OpenFOAM-2206+ form.
    _write(
        dest / "constant" / "fvOptions",
        _header("dictionary", "fvOptions")
        + f"""internalGains
{{
    type            scalarSemiImplicitSource;
    active          true;
    selectionMode   all;
    volumeMode      specific;
    sources
    {{
        T           ({su_t:.8g} 0);
    }}
}}
""",
    )
    _write(
        dest / "0" / "U",
        _header("volVectorField", "U")
        + f"""dimensions [0 1 -1 0 0 0 0];
internalField uniform (0 0 0);
boundaryField
{{
    inlet {{ type fixedValue; value uniform ({u_in} 0 0); }}
    outlet {{ type inletOutlet; inletValue uniform (0 0 0); value uniform (0 0 0); }}
    window {{ type noSlip; }}
    walls {{ type noSlip; }}
    frontAndBack {{ type noSlip; }}
}}
""",
    )
    _write(
        dest / "0" / "T",
        _header("volScalarField", "T")
        + f"""dimensions [0 0 0 1 0 0 0];
internalField uniform {t_init};
boundaryField
{{
    inlet {{ type fixedValue; value uniform {t_supply}; }}
    outlet {{ type zeroGradient; }}
    window {{ type fixedGradient; gradient uniform {window_gradient:.8g}; }}
    walls {{ type zeroGradient; }}
    frontAndBack {{ type zeroGradient; }}
}}
""",
    )
    _write(
        dest / "0" / "p_rgh",
        _header("volScalarField", "p_rgh")
        + """dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{
    inlet { type fixedFluxPressure; value uniform 0; }
    outlet { type fixedValue; value uniform 0; }
    window { type fixedFluxPressure; value uniform 0; }
    walls { type fixedFluxPressure; value uniform 0; }
    frontAndBack { type fixedFluxPressure; value uniform 0; }
}
""",
    )
    calculated = """dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{
    inlet { type calculated; value uniform 0; }
    outlet { type calculated; value uniform 0; }
    window { type calculated; value uniform 0; }
    walls { type calculated; value uniform 0; }
    frontAndBack { type calculated; value uniform 0; }
}
"""
    _write(dest / "0" / "p", _header("volScalarField", "p") + calculated)
    _write(
        dest / "0" / "alphat",
        _header("volScalarField", "alphat")
        + """dimensions [0 2 -1 0 0 0 0];
internalField uniform 0;
boundaryField
{
    inlet { type calculated; value uniform 0; }
    outlet { type calculated; value uniform 0; }
    window { type calculated; value uniform 0; }
    walls { type calculated; value uniform 0; }
    frontAndBack { type calculated; value uniform 0; }
}
""",
    )
    meta = {
        "foam_up_axis": "Y",
        "gravity_foam_m_s2": [0, -9.81, 0],
        "gravity_contract_m_s2": [0, 0, -9.81],
        "input_hash": input_hash(room),
        "nx": nx,
        "n_span": n_span,
        "n_height_bands": nys,
        "inlet_area_m2": inlet_area_m2(room),
        "window_area_m2": window_area_m2(room),
        "window_q_w_m2": q_w,
        "window_gradient_k_m": window_gradient,
        "internal_gain_w": internal_gain_w(room),
        "t_source_k_s": su_t,
        "solver": "buoyantBoussinesqSimpleFoam",
        "turbulence": "laminar",
        "assumptions": room["assumptions"],
    }
    _write(dest / "case_meta.json", json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    return dest
