#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
runtime_python="${SIMUNOW_PYTHON:-$project_root/Backend/.venv/bin/python}"
if [ ! -x "$runtime_python" ]; then
    echo "Create Backend/.venv with the manifest Python and requirements-dev.lock; or set SIMUNOW_PYTHON." >&2
    exit 1
fi
export PYTHONPATH="$project_root/Backend/src:$project_root/Backend/tests"
export PYTHONDONTWRITEBYTECODE=1
"$runtime_python" -m unittest test_doctor -v
# Non-strict inventories an unavailable environment successfully; --strict is opt-in.
exec "$runtime_python" -m simunow_worker doctor "$@"
