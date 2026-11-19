#!/bin/bash
# One bundled standalone stub compile. No model, resources, SwiftPM, download, archive, or signing.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
guard() { printf 'audit_toolchain_probe_guard=%s\n' "$1" >&2; exit 1; }
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || guard platform
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
[[ $(xcodebuild -version 2>/dev/null) == $'Xcode 26.6\nBuild version 17F113' ]] || guard xcode-version
[[ $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null) == 26.5 ]] || guard iphoneos-sdk
[[ -x /usr/bin/sandbox-exec ]] || guard sandbox-exec
source=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
scratch=$(mktemp -d "${RUNNER_TEMP:-/tmp}/vm-xcode-toolchain-only.XXXXXX") || guard scratch
cleanup() { local code=$?; trap - EXIT; rm -rf -- "$scratch"; exit "$code"; }
trap cleanup EXIT
cd "$scratch"
mkdir -p AuditToolchainProbe.xcodeproj/xcshareddata/xcschemes
cp "$source/project.pbxproj" AuditToolchainProbe.xcodeproj/
cp "$source/AuditToolchainProbe.xcscheme" AuditToolchainProbe.xcodeproj/xcshareddata/xcschemes/
cat > BuildProbe.swift <<'SWIFT'
import SwiftUI
@main struct BuildProbeApp: App {
    var body: some Scene { WindowGroup { Text("Compile only") } }
}
SWIFT
offline=(/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)')
if "${offline[@]}" xcodebuild -project AuditToolchainProbe.xcodeproj -scheme AuditToolchainProbe \
    -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation \
    -clonedSourcePackagesDirPath packages -derivedDataPath build -configuration Release \
    -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build \
    > build.log 2>&1; then
  binary=build/Build/Products/Release-iphoneos/AuditToolchainProbe.app/AuditToolchainProbe
  [[ -f $binary ]] || guard missing-device-binary
  printf 'audit_minimal_ios_build=pass\n'
else
  status=$?
  python3 "$source/native_failure.py" "$status" build.log
  exit "$status"
fi
