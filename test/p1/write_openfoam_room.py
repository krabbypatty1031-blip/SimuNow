"""Write an OpenFOAM v2512 room case from Z-up room_p1.json.

P4-07: the mesh is cut in all three directions so every window rectangle
becomes its own boundary patch (window0, window1, ...) with its own
fixedGradient. Supply/return stay full-span height bands on the x=0 wall.
The supply/return bands own the full xMin span at their heights, so a
window on xMin that would share those faces is rejected up front.
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from room_input import (
    RoomError,
    foam_xyz,
    inlet_area_m2,
    input_hash,
    internal_gain_w,
    obstacle_boxes,
    qty,
    room_box,
    window_area_m2,
    window_rects,
    window_total_w,
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
    """Keep thin bands at least two cells so checkMesh stays usable."""
    safe = [max(length, 1e-9) for length in lengths]
    total = sum(safe)
    counts = [max(min_each, int(round(target * length / total))) for length in safe]
    return counts


def _mid(lo: float, hi: float) -> float:
    return 0.5 * (lo + hi)


def _in_band(m: float, lo: float, hi: float) -> bool:
    return lo - 1e-9 <= m <= hi + 1e-9


def _blocked_cells(
    cuts_x: list[float],
    cuts_h: list[float],
    cuts_s: list[float],
    nxs: list[int],
    nhs: list[int],
    nss: list[int],
    boxes: list[dict[str, Any]],
) -> tuple[int, float, float]:
    """Cells whose centres lie inside a furniture box, in foam coordinates.

    Same selection rule as OpenFOAM boxToCell (cell-centre containment), so
    the counted blocked volume matches the cells subsetMesh will remove —
    the internal-gain source is rescaled by exactly that fluid volume, so
    the energy gate keeps accounting the draft's people/light/equipment
    watts even with furniture in the room. Total cells stay a few thousand;
    the enumeration is cheap and exact.
    """
    # Foam (x, y_up, z_span) = contract (x, z, y): convert each box once.
    foam_boxes = [
        ((box["x0"], box["z0"], box["y0"]), (box["x1"], box["z1"], box["y1"]))
        for box in boxes
    ]

    def inside(x: float, y: float, z: float) -> bool:
        return any(
            lo[0] <= x <= hi[0] and lo[1] <= y <= hi[1] and lo[2] <= z <= hi[2]
            for lo, hi in foam_boxes
        )

    blocked = 0
    blocked_volume = 0.0
    total_volume = 0.0
    for i, nx_i in enumerate(nxs):
        dx = (cuts_x[i + 1] - cuts_x[i]) / nx_i
        for sub_i in range(nx_i):
            cx = cuts_x[i] + (sub_i + 0.5) * dx
            for j, nh_j in enumerate(nhs):
                dh = (cuts_h[j + 1] - cuts_h[j]) / nh_j
                for sub_j in range(nh_j):
                    ch = cuts_h[j] + (sub_j + 0.5) * dh
                    for k, ns_k in enumerate(nss):
                        ds = (cuts_s[k + 1] - cuts_s[k]) / ns_k
                        for sub_k in range(ns_k):
                            cs = cuts_s[k] + (sub_k + 0.5) * ds
                            volume = dx * dh * ds
                            total_volume += volume
                            if inside(cx, ch, cs):
                                blocked += 1
                                blocked_volume += volume
    return blocked, blocked_volume, total_volume


def _validated_windows(room: dict[str, Any]) -> list[dict[str, Any]]:
    """Per-window rectangles with bounds and xMin band-conflict guards.

    The CLI fixture path bypasses l2_room's checks, so the writer re-asserts
    them: a window off its wall or off the room, or one that would share
    inlet/outlet faces on xMin, is an honest error, never a silent watt loss.
    """
    lx, span, height = room_box(room)
    supply_z0, supply_z1 = qty(room["supply"]["z0_m"]), qty(room["supply"]["z1_m"])
    return_z0, return_z1 = qty(room["return"]["z0_m"]), qty(room["return"]["z1_m"])
    windows = window_rects(room)
    if not windows:
        raise RoomError("room has no windows[] rectangle; the case needs a glazed patch")
    for index, item in enumerate(windows):
        wall = item.get("wall")
        if wall not in ("xMin", "xMax", "yMin", "yMax"):
            raise RoomError(f"window {index} wall {wall!r} is not one of xMin/xMax/yMin/yMax")
        # xMin/xMax windows run along contract y; yMin/yMax along contract x.
        wall_len = span if wall in ("xMin", "xMax") else lx
        s0, s1 = qty(item["s0_m"]), qty(item["s1_m"])
        z0, z1 = qty(item["z0_m"]), qty(item["z1_m"])
        if not 0 <= s0 < s1 <= wall_len + 1e-9:
            raise RoomError(f"window {index} on {wall} leaves the wall span 0..{wall_len:g} m")
        if not 0 <= z0 < z1 <= height + 1e-9:
            raise RoomError(f"window {index} on {wall} leaves the room height 0..{height:g} m")
        if wall == "xMin":
            for band, (bz0, bz1) in (("supply", (supply_z0, supply_z1)), ("return", (return_z0, return_z1))):
                if z0 < bz1 - 1e-9 and bz0 < z1 - 1e-9:
                    raise RoomError(
                        f"window {index} on xMin overlaps the {band} band z {bz0:g}..{bz1:g} m; move the window off the grille"
                    )
    return windows


def write_openfoam_room(room: dict[str, Any], dest: Path) -> Path:
    """Y-up OpenFOAM case. Sampling must convert back with contract_xyz."""
    dest = Path(dest)
    for sub in ("0", "constant", "system"):
        (dest / sub).mkdir(parents=True, exist_ok=True)

    # Contract (x, y, z) -> foam (x, y_up=contract z, z_span=contract y).
    lx, span, height = room_box(room)
    nx = int(qty(room["mesh"]["nx"]))
    n_span = int(qty(room["mesh"]["n_span"]))
    n_height = int(qty(room["mesh"]["n_height"]))
    supply_z0, supply_z1 = qty(room["supply"]["z0_m"]), qty(room["supply"]["z1_m"])
    return_z0, return_z1 = qty(room["return"]["z0_m"]), qty(room["return"]["z1_m"])
    windows = _validated_windows(room)
    windows_along_x = [item for item in windows if item["wall"] in ("yMin", "yMax")]
    windows_along_span = [item for item in windows if item["wall"] in ("xMin", "xMax")]

    # Three-direction cuts. Every window edge becomes a mesh line so each
    # rectangle is exactly a set of block faces (P4-07 geometry fidelity).
    cuts_x = _unique_heights(
        0.0,
        lx,
        *(value for item in windows_along_x for value in (qty(item["s0_m"]), qty(item["s1_m"]))),
    )
    cuts_h = _unique_heights(
        0.0,
        height,
        supply_z0,
        supply_z1,
        return_z0,
        return_z1,
        *(value for item in windows for value in (qty(item["z0_m"]), qty(item["z1_m"]))),
    )
    cuts_s = _unique_heights(
        0.0,
        span,
        *(value for item in windows_along_span for value in (qty(item["s0_m"]), qty(item["s1_m"]))),
    )
    nxs = _allocate_cells([cuts_x[i + 1] - cuts_x[i] for i in range(len(cuts_x) - 1)], nx)
    nhs = _allocate_cells([cuts_h[j + 1] - cuts_h[j] for j in range(len(cuts_h) - 1)], n_height)
    nss = _allocate_cells([cuts_s[k + 1] - cuts_s[k] for k in range(len(cuts_s) - 1)], n_span)

    # Furniture (2026-10-04): validated contract AABBs; each box becomes
    # blocked mesh cells via topoSet/subsetMesh in the pipeline.
    obstacles = obstacle_boxes(room)
    blocked_cells, blocked_volume, total_volume = (
        _blocked_cells(cuts_x, cuts_h, cuts_s, nxs, nhs, nss, obstacles) if obstacles else (0, 0.0, 0.0)
    )

    u_in = qty(room["supply"]["u_m_s"])
    t_supply = qty(room["supply"]["t_c"]) + 273.15
    t_init = qty(room["t_init_c"]) + 273.15
    t_ref = qty(room["air"]["t_ref_c"]) + 273.15
    nu = qty(room["air"]["nu"])
    pr = qty(room["air"]["pr"])
    rho = qty(room["air"]["rho"])
    cp = qty(room["air"]["cp"])
    # Fourier: q_into = -k * dT/dn_out. A negative fixedGradient turned the
    # patch into a sink (min T below supply); positive puts heat into the fluid.
    kappa = rho * cp * (nu / pr)
    # Per-window gradients: each patch injects q_i over its own rectangle.
    window_gradients = [qty(item["q_w_m2"]) / kappa for item in windows]
    window_patches = [f"window{index}" for index in range(len(windows))]
    volume = lx * span * height
    # Internal gains spread over the FLUID volume: blocked cells no longer
    # carry source, so Su is rescaled to inject the same total watts the
    # energy gate accounts (people + lights + equipment), never silently
    # less because furniture displaced air.
    volume_fluid = (total_volume or volume) - blocked_volume
    su_t = internal_gain_w(room) / (rho * cp * volume_fluid)
    end_time = int(qty(room["solver"]["end_time"]))
    seat_h = qty(room["seat_height_m"])
    far = max(room["seats"], key=lambda seat: float(seat["x_m"]))
    inlet_pt = foam_xyz(0.05, span * 0.5, 0.5 * (supply_z0 + supply_z1))
    outlet_pt = foam_xyz(0.05, span * 0.5, 0.5 * (return_z0 + return_z1))
    far_pt = foam_xyz(float(far["x_m"]), float(far["y_m"]), float(far["z_m"]))

    LOGGER.info(
        "write OF room case dest=%s nx=%s n_span=%s n_height=%s blocks=%s windows=%s",
        dest.name,
        nxs,
        nss,
        nhs,
        (len(cuts_x) - 1) * (len(cuts_h) - 1) * (len(cuts_s) - 1),
        window_patches,
    )

    # Full 3-D point lattice; block corners reference points by index.
    # One cut value per direction IS one point plane (no +1 anywhere).
    nx_pts, nh_pts, ns_pts = len(cuts_x), len(cuts_h), len(cuts_s)

    def vid(i: int, j: int, k: int) -> int:
        # i along foam x (contract x), j along foam y (height), k along foam z (span).
        return i + nx_pts * (j + nh_pts * k)

    vertices: list[str] = []
    for k in range(ns_pts):
        for j in range(nh_pts):
            for i in range(nx_pts):
                vertices.append(f"    ({cuts_x[i]:.6f} {cuts_h[j]:.6f} {cuts_s[k]:.6f})")

    def face_window(wall: str, s_mid: float, h_mid: float) -> int | None:
        """Index of the single window rectangle containing this block face, else None.

        Cuts sit on every window edge, so a boundary block face lies either
        fully inside one rectangle or fully outside all of them.
        """
        for index, item in enumerate(windows):
            if item["wall"] != wall:
                continue
            if _in_band(s_mid, qty(item["s0_m"]), qty(item["s1_m"])) and _in_band(
                h_mid, qty(item["z0_m"]), qty(item["z1_m"])
            ):
                return index
        return None

    blocks: list[str] = []
    faces: dict[str, list[str]] = {"inlet": [], "outlet": [], "walls": []}
    for name in window_patches:
        faces[name] = []

    for k in range(len(cuts_s) - 1):
        m_s = _mid(cuts_s[k], cuts_s[k + 1])
        for j in range(len(cuts_h) - 1):
            m_h = _mid(cuts_h[j], cuts_h[j + 1])
            for i in range(len(cuts_x) - 1):
                m_x = _mid(cuts_x[i], cuts_x[i + 1])
                ids = [
                    vid(i, j, k),
                    vid(i + 1, j, k),
                    vid(i + 1, j + 1, k),
                    vid(i, j + 1, k),
                    vid(i, j, k + 1),
                    vid(i + 1, j, k + 1),
                    vid(i + 1, j + 1, k + 1),
                    vid(i, j + 1, k + 1),
                ]
                blocks.append(
                    f"    hex ({' '.join(str(v) for v in ids)}) ({nxs[i]} {nhs[j]} {nss[k]}) simpleGrading (1 1 1)"
                )
                # Same face corner sets as the pre-P4-07 slab writer, so a
                # single full-span xMax window reproduces the old topology.
                xlo = f"({ids[0]} {ids[4]} {ids[7]} {ids[3]})"
                xhi = f"({ids[1]} {ids[2]} {ids[6]} {ids[5]})"
                hlo = f"({ids[0]} {ids[1]} {ids[5]} {ids[4]})"
                hhi = f"({ids[3]} {ids[7]} {ids[6]} {ids[2]})"
                slo = f"({ids[0]} {ids[3]} {ids[2]} {ids[1]})"
                shi = f"({ids[4]} {ids[5]} {ids[6]} {ids[7]})"
                if i == 0:
                    # Supply/return own the full span at their heights.
                    if _in_band(m_h, supply_z0, supply_z1):
                        faces["inlet"].append(xlo)
                    elif _in_band(m_h, return_z0, return_z1):
                        faces["outlet"].append(xlo)
                    else:
                        found = face_window("xMin", m_s, m_h)
                        (faces[window_patches[found]] if found is not None else faces["walls"]).append(xlo)
                if i == len(cuts_x) - 2:
                    # Last x interval owns the x=max plane faces.
                    found = face_window("xMax", m_s, m_h)
                    (faces[window_patches[found]] if found is not None else faces["walls"]).append(xhi)
                if j == 0:
                    faces["walls"].append(hlo)  # floor
                if j == len(cuts_h) - 2:
                    faces["walls"].append(hhi)  # ceiling
                if k == 0:
                    found = face_window("yMin", m_x, m_h)
                    (faces[window_patches[found]] if found is not None else faces["walls"]).append(slo)
                if k == len(cuts_s) - 2:
                    found = face_window("yMax", m_x, m_h)
                    (faces[window_patches[found]] if found is not None else faces["walls"]).append(shi)

    if not faces["inlet"] or not faces["outlet"]:
        raise RuntimeError("case is missing the inlet or outlet band")
    for name in window_patches:
        if not faces[name]:
            raise RuntimeError(f"window patch {name} has no faces; the rectangle missed the mesh")

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
            [patch("inlet", "patch"), patch("outlet", "patch")]
            + [patch(name, "wall") for name in window_patches]
            + [patch("walls", "wall")]
        )
        + "\n);\nmergePatchPairs ();\n",
    )
    if obstacles:
        # Foam coordinates: (x, y_up=contract z, z_span=contract y). The
        # pipeline runs topoSet then `subsetMesh fluid -patch furniture` so
        # the exposed faces become a solid `furniture` boundary patch.
        foam_boxes = "\n".join(
            f"            ({box['x0']:.6f} {box['z0']:.6f} {box['y0']:.6f}) "
            f"({box['x1']:.6f} {box['z1']:.6f} {box['y1']:.6f})"
            for box in obstacles
        )
        # v2512 (ESI) topoSetDict: `type` names the SET kind, `source` the
        # selector; `invert` carries the set type too. Verified against the
        # pinned engine by hand (2026-10-04).
        _write(
            dest / "system" / "topoSetDict",
            _header("dictionary", "topoSetDict")
            + f"""actions
(
    {{
        name    furniture;
        action  new;
        type    cellSet;
        source  boxToCell;
        boxes
        (
{foam_boxes}
        );
    }}
    {{
        name    fluid;
        action  new;
        type    cellSet;
        source  cellToCell;
        set     furniture;
    }}
    {{
        name    fluid;
        action  invert;
        type    cellSet;
    }}
);
""",
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
    window_u = "\n".join(f"    {name} {{ type noSlip; }}" for name in window_patches)
    window_t = "\n".join(
        f"    {name} {{ type fixedGradient; gradient uniform {window_gradients[index]:.8g}; }}"
        for index, name in enumerate(window_patches)
    )
    window_p_rgh = "\n".join(f"    {name} {{ type fixedFluxPressure; value uniform 0; }}" for name in window_patches)
    window_calculated = "\n".join(f"    {name} {{ type calculated; value uniform 0; }}" for name in window_patches)
    _write(
        dest / "0" / "U",
        _header("volVectorField", "U")
        + f"""dimensions [0 1 -1 0 0 0 0];
internalField uniform (0 0 0);
boundaryField
{{
    inlet {{ type fixedValue; value uniform ({u_in} 0 0); }}
    outlet {{ type inletOutlet; inletValue uniform (0 0 0); value uniform (0 0 0); }}
{window_u}
    walls {{ type noSlip; }}
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
{window_t}
    walls {{ type zeroGradient; }}
}}
""",
    )
    _write(
        dest / "0" / "p_rgh",
        _header("volScalarField", "p_rgh")
        + f"""dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{{
    inlet {{ type fixedFluxPressure; value uniform 0; }}
    outlet {{ type fixedValue; value uniform 0; }}
{window_p_rgh}
    walls {{ type fixedFluxPressure; value uniform 0; }}
}}
""",
    )
    calculated = f"""dimensions [0 2 -2 0 0 0 0];
internalField uniform 0;
boundaryField
{{
    inlet {{ type calculated; value uniform 0; }}
    outlet {{ type calculated; value uniform 0; }}
{window_calculated}
    walls {{ type calculated; value uniform 0; }}
}}
"""
    _write(dest / "0" / "p", _header("volScalarField", "p") + calculated)
    _write(
        dest / "0" / "alphat",
        _header("volScalarField", "alphat")
        + f"""dimensions [0 2 -1 0 0 0 0];
internalField uniform 0;
boundaryField
{{
    inlet {{ type calculated; value uniform 0; }}
    outlet {{ type calculated; value uniform 0; }}
{window_calculated}
    walls {{ type calculated; value uniform 0; }}
}}
""",
    )
    meta = {
        "foam_up_axis": "Y",
        "gravity_foam_m_s2": [0, -9.81, 0],
        "gravity_contract_m_s2": [0, 0, -9.81],
        "input_hash": input_hash(room),
        "nx": nxs,
        "n_span": nss,
        "n_height_bands": nhs,
        "inlet_area_m2": inlet_area_m2(room),
        # One entry per (merged) window rectangle; the patch name is the
        # contract between this case and the quality/accounting readers.
        "windows": [
            {
                "patch": window_patches[index],
                "wall": item["wall"],
                "s0_m": qty(item["s0_m"]),
                "s1_m": qty(item["s1_m"]),
                "z0_m": qty(item["z0_m"]),
                "z1_m": qty(item["z1_m"]),
                "q_w_m2": qty(item["q_w_m2"]),
                "area_m2": (qty(item["s1_m"]) - qty(item["s0_m"]))
                * (qty(item["z1_m"]) - qty(item["z0_m"])),
                "gradient_k_m": window_gradients[index],
            }
            for index, item in enumerate(windows)
        ],
        "window_area_m2": window_area_m2(room),
        "window_total_w_m2": window_total_w(room),
        "internal_gain_w": internal_gain_w(room),
        "t_source_k_s": su_t,
        "solver": "buoyantBoussinesqSimpleFoam",
        "turbulence": "laminar",
        "assumptions": room["assumptions"],
    }
    # Furniture accounting (2026-10-04): what the pipeline removes and the
    # fluid volume the rescaled internal-gain source spreads over, so the
    # energy gate's numbers stay traceable to the mesh. Only furnished
    # rooms carry the keys; the empty-room meta stays the pre-furniture
    # pinned shape.
    if obstacles:
        meta.update(
            {
                "obstacles": [
                    {
                        "id": box["id"],
                        "kind": box["kind"],
                        "x0_m": box["x0"],
                        "y0_m": box["y0"],
                        "z0_m": box["z0"],
                        "x1_m": box["x1"],
                        "y1_m": box["y1"],
                        "z1_m": box["z1"],
                    }
                    for box in obstacles
                ],
                "blocked_cells": blocked_cells,
                "blocked_volume_m3": blocked_volume,
                "fluid_volume_m3": volume_fluid,
            }
        )
    _write(dest / "case_meta.json", json.dumps(meta, indent=2, ensure_ascii=False) + "\n")
    return dest
