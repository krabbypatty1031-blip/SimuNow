"""A truthful capability probe. Does not simulate or emit numerical results."""
import argparse
import json
import logging
import os
import subprocess
from pathlib import Path

from . import __version__

# Stdout is the JSON contract. Workflow logs stay on stderr so a caller can parse doctor.
logger = logging.getLogger("simunow.worker")

# Repair text names the existing installer. Doctor must not download or run it.
REPAIR = "运行 test/engines/install_engines.sh"
EP_VERSION = "25.2.0-cf7368216c"
OF_TAG = "simunow/openfoam:2512"
OF_PLATFORM = "linux/arm64"
OF_SOLVER = "buoyantBoussinesqSimpleFoam"


def _configure_logging() -> None:
    """One stderr handler. A second doctor() in-process must not duplicate lines."""
    if logger.handlers:
        return
    logger.setLevel(logging.DEBUG)
    handler = logging.StreamHandler()
    handler.setLevel(logging.INFO)
    handler.setFormatter(logging.Formatter("%(levelname)s | %(name)s | %(message)s"))
    logger.addHandler(handler)
    logger.propagate = False


def _missing(reason: str) -> dict:
    logger.warning("not configured: %s", reason)
    return {"status": "not_configured", "repair": REPAIR}


def _engines_root() -> Path | None:
    """Resolve SIMUNOW_ENGINES_ROOT. An empty or missing directory is the same as unset."""
    raw = os.environ.get("SIMUNOW_ENGINES_ROOT", "").strip()
    if not raw:
        logger.info("SIMUNOW_ENGINES_ROOT unset")
        return None
    root = Path(raw)
    if not root.is_dir():
        logger.warning("SIMUNOW_ENGINES_ROOT is not a directory")
        return None
    logger.debug("engines root resolved")
    return root


def _probe_l1(root: Path | None) -> dict:
    """L1 is EnergyPlus. --version checks the pin without starting a simulation."""
    if root is None:
        return _missing("l1 engines root missing")
    binary = root / "EnergyPlus" / "energyplus"
    if not binary.is_file() or not os.access(binary, os.X_OK):
        logger.warning("l1 binary missing or not executable")
        return _missing("l1 binary missing")
    logger.info("probing l1 energyplus --version")
    try:
        proc = subprocess.run(
            [str(binary), "--version"],
            capture_output=True,
            text=True,
            timeout=60,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.error("l1 version probe failed: %s", exc)
        return _missing("l1 version probe failed")
    text = f"{proc.stdout}\n{proc.stderr}"
    if proc.returncode != 0 or EP_VERSION not in text:
        logger.warning("l1 version mismatch rc=%s", proc.returncode)
        return _missing("l1 version mismatch")
    logger.info("l1 configured")
    return {"status": "configured", "version": EP_VERSION}


def _probe_l2(root: Path | None) -> dict:
    """L2 is the pinned OpenFOAM image. Inspect architecture; never docker-run a solver."""
    if root is None:
        return _missing("l2 engines root missing")
    manifest_path = root / "MANIFEST.json"
    if not manifest_path.is_file():
        logger.warning("l2 MANIFEST.json missing")
        return _missing("l2 manifest missing")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        openfoam = manifest["openfoam"]
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
        logger.error("l2 manifest unreadable: %s", exc)
        return _missing("l2 manifest unreadable")
    if not isinstance(openfoam, dict):
        return _missing("l2 manifest openfoam is not an object")
    # Install manifests written before the solver pin omit the key. foamRun is never accepted.
    solver = openfoam.get("solver", OF_SOLVER)
    if solver != OF_SOLVER:
        logger.warning("l2 solver refused: %s", solver)
        return _missing("l2 solver is not buoyantBoussinesqSimpleFoam")
    if openfoam.get("local_tag") != OF_TAG or openfoam.get("platform") != OF_PLATFORM:
        logger.warning(
            "l2 pin mismatch tag=%s platform=%s",
            openfoam.get("local_tag"),
            openfoam.get("platform"),
        )
        return _missing("l2 tag or platform mismatch")
    logger.info("inspecting l2 image architecture")
    try:
        proc = subprocess.run(
            ["docker", "image", "inspect", OF_TAG, "--format", "{{.Os}}/{{.Architecture}}"],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        logger.error("l2 image inspect failed: %s", exc)
        return _missing("l2 docker inspect failed")
    arch = (proc.stdout or "").strip()
    if proc.returncode != 0 or arch != OF_PLATFORM:
        logger.warning("l2 architecture %r rc=%s", arch, proc.returncode)
        return _missing("l2 image is not linux/arm64")
    logger.info("l2 configured")
    return {"status": "configured", "platform": arch, "solver": OF_SOLVER}


def build_report() -> dict:
    """Assemble the doctor document. L0 and L3 stay P0 strings until those engines exist."""
    root = _engines_root()
    logger.debug("building doctor report")
    return {
        "protocol_version": 1,
        "worker_version": __version__,
        "status": "scaffold",
        "engines": {
            "l0": "not_configured",
            "l1": _probe_l1(root),
            "l2": _probe_l2(root),
            "l3": "not_configured",
        },
    }


def main():
    _configure_logging()
    parser = argparse.ArgumentParser(prog="simunow-worker")
    parser.add_argument("command", choices=["doctor"])
    parser.parse_args()
    # ensure_ascii stays off so the repair hint is readable Chinese, not \\u escapes.
    print(json.dumps(build_report(), ensure_ascii=False))


if __name__ == "__main__":
    main()
