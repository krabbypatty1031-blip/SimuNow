#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
project_key="$(printf '%s' "$project_root" | cksum | awk '{print $1}')"
# Keep signed test bundles outside Desktop/Documents File Provider directories.
build_root="${SIMUNOW_BUILD_DIR:-${TMPDIR:-/tmp}/SimuNow-build-$project_key}"
mkdir -p "$build_root"
export CLANG_MODULE_CACHE_PATH="$build_root/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/ModuleCache"
mode="${1:-all}"
case "$mode" in
    test)
        swift test --package-path "$project_root/Packages/SimuKit" --scratch-path "$build_root/SwiftPackage" ;;
    contracts)
        "$project_root/Scripts/check_contracts.sh" ;;
    runtime)
        "$project_root/Scripts/check_runtime.sh" ;;
    mac)
        xcodebuild -project "$project_root/SimuNow.xcodeproj" -scheme SimuNowMac -configuration Debug -destination 'platform=macOS' -derivedDataPath "$build_root/macOS" CODE_SIGNING_ALLOWED=NO build ;;
    ios)
        xcodebuild -project "$project_root/SimuNow.xcodeproj" -scheme SimuNowiOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath "$build_root/iOS" CODE_SIGNING_ALLOWED=NO build ;;
    all)
        "$0" contracts
        "$0" mac
        "$0" ios ;;
    *)
        echo "Usage: Scripts/check.sh [all|test|contracts|runtime|mac|ios]" >&2
        exit 2 ;;
esac
