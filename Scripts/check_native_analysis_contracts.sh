#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
contract_python="${SIMUNOW_PYTHON:-$project_root/Backend/.venv/bin/python}"
if [ ! -x "$contract_python" ]; then
    echo "Use Backend locked developer environment or set SIMUNOW_PYTHON." >&2; exit 1
fi
"$contract_python" - <<'PY'
from importlib.metadata import version
if version('jsonschema') != '4.26.0': raise SystemExit('Use locked jsonschema 4.26.0')
PY
export PYTHONDONTWRITEBYTECODE=1
"$contract_python" "$project_root/Scripts/generate_native_analysis_schemas.py" --check
"$contract_python" "$project_root/Scripts/generate_consumer_schemas.py" --check
export SIMUNOW_NATIVE_CONTRACT_DIR
SIMUNOW_NATIVE_CONTRACT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/SimuNow-native-contracts.XXXXXX")"
trap 'rm -rf "$SIMUNOW_NATIVE_CONTRACT_DIR"' EXIT
export SIMUNOW_CONSUMER_OUTPUT_DIR="$SIMUNOW_NATIVE_CONTRACT_DIR/consumer"
"$project_root/Scripts/check.sh" test
"$contract_python" "$project_root/Scripts/validate_native_analysis_contracts.py" "$SIMUNOW_NATIVE_CONTRACT_DIR"

"$contract_python" "$project_root/Scripts/check_consumer_contracts.py" "$SIMUNOW_CONSUMER_OUTPUT_DIR"
