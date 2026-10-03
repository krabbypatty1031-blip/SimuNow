"""OpenFOAM ascii field helpers shared by the room pipeline."""

from __future__ import annotations

import re
from pathlib import Path

from room_input import RoomError


def parse_scalar_field(text: str) -> list[float]:
    body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    idx = body.find("internalField")
    if idx < 0:
        raise RoomError("OpenFOAM field has no internalField")
    body = body[idx:]
    uniform = re.search(r"internalField\s+uniform\s+([-+0-9.eE]+)\s*;", body)
    if uniform:
        return [float(uniform.group(1))]
    listed = re.search(
        r"internalField\s+nonuniform\s+List<scalar>\s*(\d+)\s*\(\s*(.*?)\s*\)\s*;",
        body,
        re.S,
    )
    if not listed:
        raise RoomError("unrecognised scalar internalField")
    count = int(listed.group(1))
    values = [float(token) for token in listed.group(2).split()]
    if len(values) != count:
        raise RoomError(f"scalar field declared {count} values but parsed {len(values)}")
    return values


def parse_vector_field(text: str) -> list[tuple[float, float, float]]:
    body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    idx = body.find("internalField")
    if idx < 0:
        raise RoomError("OpenFOAM field has no internalField")
    body = body[idx:]
    uniform = re.search(
        r"internalField\s+uniform\s+\(\s*([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*\)\s*;",
        body,
    )
    if uniform:
        return [tuple(float(part) for part in uniform.groups())]  # type: ignore[return-value]
    listed = re.search(
        r"internalField\s+nonuniform\s+List<vector>\s*(\d+)\s*\(\s*(.*?)\s*\)\s*;",
        body,
        re.S,
    )
    if not listed:
        raise RoomError("unrecognised vector internalField")
    count = int(listed.group(1))
    raw = re.findall(r"\(\s*([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*\)", listed.group(2))
    values = [(float(a), float(b), float(c)) for a, b, c in raw]
    if len(values) != count:
        raise RoomError(f"vector field declared {count} values but parsed {len(values)}")
    return values


def parse_patch_uniform(text: str, patch: str) -> float | None:
    """Uniform scalar on a named patch, or None if the patch is nonuniform/missing."""
    body = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    match = re.search(
        rf"{re.escape(patch)}\s*\{{[^}}]*?uniform\s+([-+0-9.eE]+)\s*;",
        body,
        re.S,
    )
    if not match:
        return None
    return float(match.group(1))


def latest_time(case: Path) -> Path:
    found: list[tuple[float, Path]] = []
    for child in case.iterdir():
        if not child.is_dir() or child.name in {"0", "constant", "system", "postProcessing"}:
            continue
        try:
            found.append((float(child.name), child))
        except ValueError:
            continue
    if not found:
        raise RoomError(f"solver wrote no time directory in {case.name}")
    return max(found)[1]


def _mesh_body(text: str, keyword: str) -> str:
    """Body of a top-level polyMesh list such as `points ( ... )`.

    FoamFile headers carry no parentheses, so the first '(' after the keyword
    opens the list and the last ')' in the file closes it.
    """
    body = re.sub(r"//.*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))
    idx = body.find(keyword)
    if idx < 0:
        raise RoomError(f"polyMesh list '{keyword}' not found")
    start = body.find("(", idx)
    end = body.rfind(")")
    if start < 0 or end <= start:
        raise RoomError(f"polyMesh list '{keyword}' is not a parenthesised list")
    return body[start + 1 : end]


def parse_boundary_patch(text: str, patch: str) -> tuple[int, int]:
    """(startFace, nFaces) of a named boundary patch; missing is an error."""
    body = re.sub(r"//.*", "", re.sub(r"/\*.*?\*/", "", text, flags=re.S))
    match = re.search(rf"\b{re.escape(patch)}\s*\{{(.*?)\}}", body, re.S)
    if not match:
        raise RoomError(f"boundary patch '{patch}' not found")
    block = match.group(1)
    start = re.search(r"startFace\s+(\d+)\s*;", block)
    count = re.search(r"nFaces\s+(\d+)\s*;", block)
    if not start or not count:
        raise RoomError(f"boundary patch '{patch}' lacks startFace/nFaces")
    return int(start.group(1)), int(count.group(1))


def parse_point_list(text: str) -> list[tuple[float, float, float]]:
    vectors = re.findall(
        r"\(\s*([-+0-9.eE]+)\s+([-+0-9.eE]+)\s+([-+0-9.eE]+)\s*\)",
        _mesh_body(text, "points"),
    )
    if not vectors:
        raise RoomError("polyMesh points list is empty")
    return [(float(a), float(b), float(c)) for a, b, c in vectors]


def parse_face_list(text: str) -> list[list[int]]:
    items = re.findall(r"\(([\d\s]+)\)", _mesh_body(text, "faces"))
    if not items:
        raise RoomError("polyMesh faces list is empty")
    return [[int(token) for token in item.split()] for item in items]


def parse_owner_list(text: str) -> list[int]:
    body = _mesh_body(text, "owner")
    tokens = body.split()
    if not tokens:
        raise RoomError("polyMesh owner list is empty")
    try:
        return [int(token) for token in tokens]
    except ValueError as exc:
        raise RoomError("polyMesh owner list holds non-label tokens") from exc
