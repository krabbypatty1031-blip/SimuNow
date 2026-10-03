#!/bin/bash
# Produces an unsigned development archive, never uploads, notarizes or submits it.
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
platform="${1:-mac}"
candidate_root="${SIMUNOW_CANDIDATE_DIR:-${TMPDIR:-/tmp}/SimuNow-candidate}"
case "$platform" in
    mac) scheme=SimuNowMac; destination='generic/platform=macOS' ;;
    ios) scheme=SimuNowiOS; destination='generic/platform=iOS' ;;
    *) echo 'Usage: prepare_release_candidate.sh [mac|ios]' >&2; exit 2 ;;
esac
command -v xcodebuild >/dev/null || { echo 'Xcode required; no Apple archive can be produced in this environment.' >&2; exit 1; }
mkdir -p "$candidate_root"
python3 "$project_root/Scripts/generate_consumer_schemas.py" --check
"$project_root/Scripts/check.sh" test
xcodebuild -project "$project_root/SimuNow.xcodeproj" -scheme "$scheme" -configuration Release \
    -destination "$destination" -archivePath "$candidate_root/$scheme.xcarchive" \
    -derivedDataPath "$candidate_root/$scheme-derived" CODE_SIGNING_ALLOWED=NO archive
echo "Unsigned development archive: $candidate_root/$scheme.xcarchive"
echo 'Signing, clean installation, platform QA and user-approved distribution remain separate gates.'
