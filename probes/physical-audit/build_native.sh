#!/bin/bash
# Deliberately not a workflow. No retrieval, signing, installation, or upload.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
if [[ $# != 8 ]]; then
  echo "usage: build_native.sh ORIGINAL_IPA REVIEWED_RECEIPT RECEIPT_SHA STAGED_MODELS STAGED_PYTHON FROZEN_GRAPH GRAPH_SHA EMPTY_OUTPUT_PATH" >&2
  exit 2
fi
[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]]
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
gate=probes/physical-audit/packaging_gate.py
baseline=$1 approval=$2 approvalSHA=$3 models=$4 sdk=$5 graph=$6 graphSHA=$7 output=$8
for input in "$baseline" "$approval" "$models" "$sdk" "$graph" "$output"; do
  [[ $input == /* && ! -L $input ]] || { echo 'Use absolute paths, without links' >&2; exit 2; }
done
[[ ! -e $output && -f $graph && $approvalSHA =~ ^[a-f0-9]{64}$ && $graphSHA =~ ^[a-f0-9]{64}$ ]]
[[ $models != "$ROOT/"* && $sdk != "$ROOT/"* && $output != "$ROOT/"* ]]
[[ $(shasum -a 256 "$graph" | awk '{print $1}') == "$graphSHA" ]]
git diff --quiet && git diff --cached --quiet
[[ -z $(git ls-files --others --exclude-standard) ]]
test -n "${AUDIT_OFFLINE_SOURCE_PACKAGES:?Use an already resolved exact local Xcode dependency cache}"
[[ $AUDIT_OFFLINE_SOURCE_PACKAGES == /* && -d $AUDIT_OFFLINE_SOURCE_PACKAGES && ! -L $AUDIT_OFFLINE_SOURCE_PACKAGES ]]
test -n "${AUDIT_XCODEGEN_PATH:?Use the reviewed pinned XcodeGen binary}"
test -n "${AUDIT_XCODEGEN_SHA256:?Pin the reviewed XcodeGen binary hash}"
[[ $AUDIT_XCODEGEN_PATH == /* && -x $AUDIT_XCODEGEN_PATH && ! -L $AUDIT_XCODEGEN_PATH ]]
[[ $(shasum -a 256 "$AUDIT_XCODEGEN_PATH" | awk '{print $1}') == "$AUDIT_XCODEGEN_SHA256" ]]
common=(--baseline "$baseline" --approval "$approval" --approval-sha256 "$approvalSHA")
approval_binding=$(python3 "$gate" preflight "${common[@]}")
xcode=$(xcodebuild -version | sed -n '1p')
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
python3 - "$approval_binding" "$graphSHA" "$AUDIT_XCODEGEN_SHA256" "$xcode" "$sdk_version" <<'PY_BIND'
import json
import sys
p = json.loads(sys.argv[1])
if [p[key] for key in ("graphSHA256", "xcodegenSHA256", "xcodeVersion", "iphoneOSSDK")] != sys.argv[2:]:
    sys.exit("Native tools or frozen graph differ from reviewed inputs")
PY_BIND
# Canonical provenance must agree with exactly the runtime that is about to be linked.
python3 tools/vendored_fluid.py
candidate=$(git rev-parse HEAD)
mkdir "$output"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/vm-native-audit.XXXXXX")
src="$scratch/source"
git worktree add --detach "$src" "$candidate"
cd "$src"
check_original() {
  python3 "$gate" preflight "${common[@]}" >/dev/null || return 1
}
cleanup() {
  local code=$?
  trap - EXIT
  if ! check_original; then echo 'Baseline verification failed; retain scratch and withhold audit output' >&2; exit 1; fi
  if ((code != 0)); then echo "Withhold unverified output; clean scratch retained at $scratch" >&2; fi
  exit "$code"
}
trap cleanup EXIT
offline=(/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)')
python3 probes/physical-audit/prepare.py .physical-audit-src
python3 "$gate" stage "${common[@]}" --staged "$models" --sdk "$sdk"
"${offline[@]}" python3 probes/mkv-f5-ios/generate.py .strict-f5-fixture
"${offline[@]}" python3 tools/create_diagnostic_collection.py
cp .physical-audit-src/project.yml physical-audit-project.yml
# Use pinned dependency checkout notices, original code notices, and updated ASR attribution.
cp -R "$AUDIT_OFFLINE_SOURCE_PACKAGES" "$scratch/SourcePackages"
"${offline[@]}" python3 tools/character_package.py notices \
  --checkouts "$scratch/SourcePackages/checkouts" --resolved "$graph" --resources .physical-audit-assets
"${offline[@]}" "$AUDIT_XCODEGEN_PATH" generate --spec physical-audit-project.yml
project=VoiceMatrixPhysicalAudit.xcodeproj
resolved="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$resolved")"
cp "$graph" "$resolved"
"${offline[@]}" xcodebuild -project "$project" -scheme VoiceMatrixPhysicalAudit \
  -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation \
  -clonedSourcePackagesDirPath "$scratch/SourcePackages" -derivedDataPath "$scratch/build" -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
cmp "$graph" "$resolved"
[[ $(shasum -a 256 "$resolved" | awk '{print $1}') == "$graphSHA" ]]
app="$scratch/build/Build/Products/Release-iphoneos/VoiceMatrixPhysicalAudit.app"
mkdir "$scratch/Payload"
cp -R "$app" "$scratch/Payload/"
# Stage only in scratch until all model/fixture/identity/native-package checks pass.
ipa="$scratch/VoiceMatrix-Physical-Audit.ipa"
python3 tools/package_ipa.py "$scratch/Payload" "$ipa"
python3 "$gate" inspect "${common[@]}" --ipa "$ipa" --app "$app" --fixture .strict-f5-fixture > "$scratch/audit-proof.json"
check_original
cp "$scratch/audit-proof.json" "$output/audit-proof.json"
cp "$ipa" "$output/VoiceMatrix-Physical-Audit.ipa"
[[ $(shasum -a 256 "$output/VoiceMatrix-Physical-Audit.ipa" | awk '{print $1}') == $(shasum -a 256 "$ipa" | awk '{print $1}') ]]
printf 'Unsigned local-only audit candidate. Verify signer identity and physical test separately.\n'
