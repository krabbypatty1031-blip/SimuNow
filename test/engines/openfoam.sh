#!/usr/bin/env bash
# Run an OpenFOAM command against a case directory via the pinned Linux image.
# Why Docker: ESI OpenFOAM is a Linux runtime; this wrapper keeps Mac paths out
# of solver invocation so iOS targets never see it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
IMAGE="simunow/openfoam:2512"
if [[ -f "$ROOT/MANIFEST.json" ]]; then
  IMAGE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["openfoam"]["local_tag"])' "$ROOT/MANIFEST.json")"
fi

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <case-dir> <openfoam-command> [args...]" >&2
  exit 2
fi

CASE="$(cd "$1" && pwd)"
shift

# Entrypoint cds to $HOME, so solvers need -case on the bind mount.
# Empty extra=() plus set -u makes "${extra[@]}" unbound on this bash.
cmd=(docker run --rm --platform linux/arm64 -v "$CASE:/work" -w /work "$IMAGE" "$@")
if [[ "${1:-}" != "bash" ]]; then
  cmd+=(-case /work)
fi
"${cmd[@]}"
