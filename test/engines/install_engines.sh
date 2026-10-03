#!/usr/bin/env bash
# Install EnergyPlus (native macOS arm64 tree) and pin the OpenFOAM Linux
# container used by verify_engines.py. Why a folder install + Docker, not brew:
# EnergyPlus must be relocatable under test/; OpenFOAM's first-class runtime
# is Linux, and this machine's Docker daemon is already linux/arm64.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TEST_ROOT="$(cd "$ROOT/.." && pwd)"
WEATHER_DIR="$ROOT/weather"
mkdir -p "$ROOT" "$WEATHER_DIR"

# Pin exact artifacts so doctor/verify reports are comparable across machines.
EP_VERSION="25.2.0"
EP_BUILD="cf7368216c"
EP_ARCHIVE="EnergyPlus-${EP_VERSION}-${EP_BUILD}-Darwin-macOS13-arm64.tar.gz"
EP_DIR_NAME="EnergyPlus-${EP_VERSION}-${EP_BUILD}-Darwin-macOS13-arm64"
EP_URL="https://github.com/NREL/EnergyPlus/releases/download/v${EP_VERSION}/${EP_ARCHIVE}"

OF_IMAGE="opencfd/openfoam-run:2512"
OF_PLATFORM="linux/arm64"

EPW_NAME="CHN_Hong.Kong.SAR.450070_CityUHK.epw"
EPW_URL="https://energyplus-weather.s3.amazonaws.com/asia_wmo_region_2/CHN/CHN_Hong.Kong.SAR.450070_CityUHK/${EPW_NAME}"

log() { printf '%s | %s\n' "$(date -u +%H:%M:%S)" "$*"; }

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd tar
need_cmd python3
need_cmd docker

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not running" >&2
  exit 1
fi

download() {
  local url="$1" dest="$2"
  if [[ -f "$dest" && -s "$dest" ]]; then
    log "reuse $(basename "$dest")"
    return 0
  fi
  log "download $url"
  curl -L --fail --retry 3 --retry-delay 2 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
}

# --- EnergyPlus: extract a relocatable tree, then drop Gatekeeper quarantine.
if [[ ! -x "$ROOT/$EP_DIR_NAME/energyplus" ]]; then
  download "$EP_URL" "$ROOT/$EP_ARCHIVE"
  log "extract $EP_ARCHIVE"
  tar -xzf "$ROOT/$EP_ARCHIVE" -C "$ROOT"
fi
chmod +x "$ROOT/$EP_DIR_NAME/energyplus" || true
if command -v xattr >/dev/null 2>&1; then
  xattr -dr com.apple.quarantine "$ROOT/$EP_DIR_NAME" 2>/dev/null || true
fi
ln -sfn "$EP_DIR_NAME" "$ROOT/EnergyPlus"

# --- Weather: P0 IDF uses a Hong Kong representative day, not Chicago defaults.
if [[ ! -s "$WEATHER_DIR/$EPW_NAME" ]]; then
  if ! download "$EPW_URL" "$WEATHER_DIR/$EPW_NAME"; then
    log "Hong Kong EPW download failed; EnergyPlus example weather remains a fallback"
  fi
fi

# --- OpenFOAM: native Apple Silicon Linux container, not qemu/x86_64.
log "docker pull --platform $OF_PLATFORM $OF_IMAGE"
docker pull --platform "$OF_PLATFORM" "$OF_IMAGE"
docker tag "$OF_IMAGE" simunow/openfoam:2512

python3 - "$ROOT" "$EP_VERSION" "$EP_BUILD" "$EP_DIR_NAME" "$OF_IMAGE" "$OF_PLATFORM" "$EPW_NAME" <<'PY'
"""Write MANIFEST.json so verify_engines.py does not re-parse shell constants."""
import hashlib, json, sys, platform, shutil, subprocess
from pathlib import Path

def sha256_file(path: Path) -> str | None:
    # Hash the EPW bytes in the manifest so a swapped weather file is visible.
    if not path.is_file():
        return None
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

root = Path(sys.argv[1])
ep_version, ep_build, ep_dir, of_image, of_platform, epw_name = sys.argv[2:]
ep_bin = root / ep_dir / "energyplus"
epw = root / "weather" / epw_name
# version_sha256 covers the build id, not only the major.minor.patch string.
version_id = f"{ep_version}-{ep_build}"
version_sha256 = hashlib.sha256(version_id.encode("utf-8")).hexdigest()
inspect = subprocess.check_output(
    ["docker", "image", "inspect", of_image, "--format", "{{.Id}} {{.Os}}/{{.Architecture}}"],
    text=True,
).strip()
manifest = {
    "host": {"system": platform.system(), "machine": platform.machine()},
    "energyplus": {
        "version": ep_version,
        "root": str(root / ep_dir),
        "binary": str(ep_bin),
        "present": ep_bin.is_file(),
        "weather": str(epw) if epw.is_file() else None,
        "epw_sha256": sha256_file(epw),
        "version_sha256": version_sha256,
    },
    "openfoam": {
        "image": of_image,
        "local_tag": "simunow/openfoam:2512",
        "platform": of_platform,
        "inspect": inspect,
        "note": "Linux container; Mac App must not call this from iOS.",
    },
}
(root / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
print(json.dumps(manifest, indent=2))
PY

log "install complete"
log "EnergyPlus: $ROOT/EnergyPlus/energyplus"
log "OpenFOAM image: $OF_IMAGE"
