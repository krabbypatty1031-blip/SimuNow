#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
contract_python="${SIMUNOW_PYTHON:-$project_root/Backend/.venv/bin/python}"
if [ ! -x "$contract_python" ]; then
    echo "Create a virtual environment and install Backend/requirements-dev.lock; set SIMUNOW_PYTHON to its Python."
    exit 1
fi
"$contract_python" - <<'PY'
from importlib.metadata import version
if version('pydantic') != '2.13.4' or version('jsonschema') != '4.26.0':
    raise SystemExit('Use the locked Backend/requirements-dev.lock dependencies.')
PY
export PYTHONPATH="$project_root/Backend/src:$project_root/Backend/tests"
export PYTHONDONTWRITEBYTECODE=1
export SIMUNOW_PYTHON="$contract_python"
export SIMUNOW_CONTRACT_DIR
SIMUNOW_CONTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SimuNow-contracts.XXXXXX")"
trap 'rm -rf "$SIMUNOW_CONTRACT_DIR"' EXIT
"$contract_python" "$project_root/Scripts/generate_domain_models.py" --check
"$contract_python" -m simunow_worker.models.schema --check
"$contract_python" -m unittest discover -s "$project_root/Backend/tests" -v
"$contract_python" "$project_root/Backend/tests/contract_exchange.py" prepare "$SIMUNOW_CONTRACT_DIR"
"$project_root/Scripts/check.sh" test
"$contract_python" "$project_root/Backend/tests/contract_exchange.py" verify "$SIMUNOW_CONTRACT_DIR"
