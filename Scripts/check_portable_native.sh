#!/bin/bash
# Foundation-only verification on Linux. It does not validate Apple UI, PDF or RoomPlan.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
: "${SIMUNOW_SWIFT_CRYPTO_PATH:?Set SIMUNOW_SWIFT_CRYPTO_PATH to an existing apple/swift-crypto checkout}"
portable_root="${SIMUNOW_PORTABLE_DIR:-${TMPDIR:-/tmp}/SimuNow-portable}"
mkdir -p "$portable_root"
python3 - "$project_root" "$portable_root" "$SIMUNOW_SWIFT_CRYPTO_PATH" <<'PY'
import json
from pathlib import Path
import sys
repo, root, crypto = map(Path, sys.argv[1:])
sources = root / 'Sources'
sources.mkdir(exist_ok=True)
for module in ('SimuCore', 'SimuSimulation', 'SimuReporting'):
    path = sources / module
    if not path.exists():
        path.symlink_to(repo / 'Packages/SimuKit/Sources' / module, target_is_directory=True)
workspace = sources / 'SimuWorkspaceValues'
workspace.mkdir(exist_ok=True)
for relative in ('Templates/ProjectTemplates.swift', 'Scenarios/ScenarioEditing.swift', 'Capture/RoomCaptureConversion.swift'):
    target = workspace / Path(relative).name
    if not target.exists(): target.symlink_to(repo / 'Packages/SimuKit/Sources/SimuWorkspace' / relative)
shim = sources / 'CryptoKit'
shim.mkdir(exist_ok=True)
(shim / 'Export.swift').write_text('@_exported import Crypto\n')
tests = root / 'Tests'
tests.mkdir(exist_ok=True)
if not (tests / 'SimuConsumerTests').exists():
    (tests / 'SimuConsumerTests').symlink_to(repo / 'Packages/SimuKit/Tests/SimuConsumerTests', target_is_directory=True)
workflow = tests / 'SimuConsumerValueTests'
workflow.mkdir(exist_ok=True)
value_tests = workflow / 'ConsumerValueWorkflowTests.swift'
if not value_tests.exists(): value_tests.symlink_to(repo / 'Packages/SimuKit/Tests/SimuConsumerWorkflowTests/ConsumerValueWorkflowTests.swift')
(root / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "SimuNowPortable", dependencies: [.package(path: CRYPTO_PATH)], targets: [
    .target(name: "CryptoKit", dependencies: [.product(name: "Crypto", package: CRYPTO_NAME)]),
    .target(name: "SimuCore", resources: [.process("Resources")]),
    .target(name: "SimuSimulation", dependencies: ["SimuCore", "CryptoKit"]),
    .target(name: "SimuReporting", dependencies: ["SimuCore", "CryptoKit"]),
    .target(name: "SimuWorkspace", dependencies: ["SimuCore"], path: "Sources/SimuWorkspaceValues"),
    .testTarget(name: "SimuConsumerTests", dependencies: ["SimuCore", "SimuSimulation", "SimuReporting"]),
    .testTarget(name: "SimuConsumerValueTests", dependencies: ["SimuCore", "SimuSimulation", "SimuWorkspace"])
])
'''.replace('CRYPTO_PATH', json.dumps(str(crypto))).replace('CRYPTO_NAME', json.dumps(crypto.name)))
PY
export CLANG_MODULE_CACHE_PATH="$portable_root/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$portable_root/ModuleCache"
export SIMUNOW_CONSUMER_OUTPUT_DIR="$portable_root/ContractOutput"
swift test --configuration "${SIMUNOW_PORTABLE_CONFIGURATION:-debug}" --package-path "$portable_root" --cache-path "$portable_root/Cache" --config-path "$portable_root/Config" --security-path "$portable_root/Security" --jobs 4
python3 "$project_root/Scripts/check_consumer_contracts.py" "$SIMUNOW_CONSUMER_OUTPUT_DIR"
