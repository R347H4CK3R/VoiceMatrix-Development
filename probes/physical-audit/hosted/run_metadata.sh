#!/bin/bash
# Hosted macOS build, deliberately not invoked by any installed workflow.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
fail_guard() { printf 'audit_arm64_failed_guard=%s\n' "$1" >&2; exit 1; }
root=$(git rev-parse --show-toplevel 2>/dev/null) || fail_guard checkout
cd "$root" || fail_guard checkout-directory
[[ ${GITHUB_ACTIONS:-} == true && ${GITHUB_REPOSITORY:-} == R347H4CK3R/VoiceMatrix-Development ]] || fail_guard repository
[[ ${GITHUB_REF:-} == refs/heads/verification/physical-audit-arm64 && ${GITHUB_RUN_ATTEMPT:-} == 1 ]] || fail_guard branch-or-attempt
[[ $(uname -s) == Darwin && $(uname -m) == arm64 && $# == 4 ]] || fail_guard platform-or-arity
expected_source=$1 expected_tree=$2 receipt=$3 receipt_sha=$4
[[ $expected_source =~ ^[a-f0-9]{40}$ && $expected_tree =~ ^[a-f0-9]{40}$ && $receipt_sha =~ ^[a-f0-9]{64}$ ]] || fail_guard source-identity-format
[[ ${GITHUB_SHA:-} == "$expected_source" && $(git rev-parse HEAD 2>/dev/null) == "$expected_source" ]] || fail_guard source-sha
[[ $(git rev-parse HEAD^{tree} 2>/dev/null) == "$expected_tree" ]] || fail_guard source-tree
[[ $(git rev-parse 42da8f3ed18ca1c0f1462032db5dc05ce77362a1^{tree} 2>/dev/null) == 24e298cb887b1a6bf19c177c0733e06f5a474bfc ]] || fail_guard exact-asr-runtime
[[ $(git rev-parse 4ed344a8bb859e841c35041f3f07b9510a930492^{tree} 2>/dev/null) == 53e26cfe17017df02c2c6fdc1e63a8c0d6f3ba37 ]] || fail_guard exact-strict-base
git diff --quiet && git diff --cached --quiet || fail_guard modified-checkout
[[ -z $(git ls-files --others --exclude-standard) ]] || fail_guard unexpected-untracked-files
[[ $(date -u +%F) == 2026-11-19 ]] || fail_guard approval-utc-date
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
[[ -d $DEVELOPER_DIR ]] || fail_guard xcode-path
[[ $(xcodebuild -version 2>/dev/null) == $'Xcode 26.6\nBuild version 17F113' ]] || fail_guard xcode-version-26-6-build-17F113
[[ $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null) == 26.5 ]] || fail_guard iphoneos-sdk-26-5
command -v python3 >/dev/null || fail_guard python3
python3 -c 'import sys; raise SystemExit(sys.version_info[:2] != (3,12))' || fail_guard python-3-12
[[ -x /usr/bin/sandbox-exec ]] || fail_guard sandbox-exec

# Anticipated max data before compile: baseline 1.331GB, model+tools 1.40GB,
# one scratch app+archive ~3GB; require surplus for source dependency/build layers.
disk_kib() { df -Pk "$root" | awk 'END { print $4 }'; }
disk_guard() {
  local available
  available=$(disk_kib)
  [[ $available =~ ^[0-9]+$ ]] || fail_guard disk-measurement
  if [[ $available -lt $1 ]]; then
    printf 'audit_arm64_disk_available_kib=%s;required_kib=%s\n' "$available" "$1" >&2
    fail_guard "$2"
  fi
}
disk_guard 10485760 disk-before-tooling
work=$(mktemp -d "$root/.audit-transient.XXXXXX") || fail_guard scratch-directory
chmod 0700 "$work"
stage=verified-receipt
cleanup() {
  saved=$?
  trap - EXIT
  if ((saved != 0)); then printf 'audit_arm64_failed_stage=%s\n' "$stage"; fi
  rm -rf -- "$work"
  exit "$saved"
}
trap cleanup EXIT
gate=probes/physical-audit/packaging_gate.py
hosted=probes/physical-audit/hosted
graph="$work/frozen/Package.resolved"
graphsha=2d2f397374be883181f421002ba25ef80231dab94ed331d7651bb4ebe68ee5f6
mkdir "$work/frozen"
stage=derive-canonical-vendored-graph
python3 "$hosted/verify_graph.py" seed "$graph" > "$work/graph-derive.log" 2>&1 || fail_guard derive-canonical-vendored-graph
[[ $(shasum -a 256 "$graph" | awk '{print $1}') == "$graphsha" ]] || fail_guard frozen-package-graph
stage=verified-receipt
python3 - "$gate" "$receipt" "$receipt_sha" <<'PY_RECEIPT'
import importlib.util, json, sys
from pathlib import Path
path, receipt, sha = sys.argv[1:]
s = importlib.util.spec_from_file_location("gate", path)
m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
p = Path(receipt)
if not p.is_file() or p.is_symlink() or p.stat().st_size > 4096 or m.digest(p) != sha:
    sys.exit("Missing externally approved exact receipt")
r = json.loads(p.read_bytes())
m.require_receipt(r)
if r["approvalDateUTC"] != "2026-11-19" or r["xcodeVersion"] != "Xcode 26.6" or r["iphoneOSSDK"] != "26.5":
    sys.exit("Clearance receipt does not bind this toolchain")
PY_RECEIPT

offline=(/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)')
stage=official-homebrew-ffmpeg
[[ -x /opt/homebrew/bin/brew ]] || fail_guard official-arm64-homebrew
# Only the official default formula source, with caches scoped to this disposable run.
if ! command -v ffmpeg >/dev/null || ! command -v ffprobe >/dev/null; then
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ANALYTICS=1 \
    HOMEBREW_CACHE="$work/brew-cache" /opt/homebrew/bin/brew install ffmpeg > "$work/brew.log" 2>&1 || fail_guard homebrew-ffmpeg-install
fi
ffmpeg=$(command -v ffmpeg) || fail_guard ffmpeg-not-on-path
ffprobe=$(command -v ffprobe) || fail_guard ffprobe-not-on-path
[[ $ffmpeg == /opt/homebrew/bin/ffmpeg && $ffprobe == /opt/homebrew/bin/ffprobe ]] || fail_guard media-tool-not-from-approved-prefix
for tool in "$ffmpeg" "$ffprobe"; do
  version=$("$tool" -version 2>/dev/null | awk 'NR == 1 { print $3 }') || fail_guard media-tool-version-execution
  checksum=$(shasum -a 256 "$tool" | awk '{print $1}') || fail_guard media-tool-binary-sha
  [[ $version =~ ^[A-Za-z0-9._+-]+$ && $checksum =~ ^[a-f0-9]{64}$ ]] || fail_guard media-tool-metadata-format
  printf 'audit_media_tool=%s;version=%s;binary_sha256=%s\n' "${tool##*/}" "$version" "$checksum"
done
"$ffmpeg" -hide_banner -encoders > "$work/encoders.log" 2>&1 || fail_guard ffmpeg-encoder-inventory
grep -Eq '[[:space:]]libx264[[:space:]]' "$work/encoders.log" || fail_guard ffmpeg-libx264
grep -Eq '[[:space:]]aac[[:space:]]' "$work/encoders.log" || fail_guard ffmpeg-aac
disk_guard 10485760 disk-after-tooling-before-model-fetch
stage=source-tooling
# Verify clean exact runtime before the local ephemeral build mutates ignored directories.
"${offline[@]}" python3 probes/physical-audit/prepare.py .physical-audit-src > "$work/source.log" 2>&1
"${offline[@]}" python3 tools/vendored_fluid.py >> "$work/source.log" 2>&1
"${offline[@]}" python3 tools/vendored_onnx.py >> "$work/source.log" 2>&1
stage=pinned-xcodegen
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 --max-filesize 30000000 \
  https://github.com/yonaskolb/XcodeGen/releases/download/2.44.1/xcodegen.zip -o "$work/xcodegen.zip"
[[ $(shasum -a 256 "$work/xcodegen.zip" | awk '{print $1}') == a2e905fb68446e9bb4008cdfe2e13e3f176d0cbcca828b71770f8e53fca91b73 ]]
unzip -q "$work/xcodegen.zip" 'xcodegen/bin/xcodegen' -d "$work"
XCODEGEN="$work/xcodegen/bin/xcodegen"
[[ -x $XCODEGEN && ! -L $XCODEGEN ]]
[[ $(shasum -a 256 "$XCODEGEN" | awk '{print $1}') == a450f63bdd650c280cfce0fef6c94dbb19c5bf8dc32811361fd5d2e912718503 ]]
python3 - "$receipt" "$XCODEGEN" <<'PY_TOOL'
import hashlib, json, sys
from pathlib import Path
approval, binary = map(Path, sys.argv[1:])
if hashlib.sha256(binary.read_bytes()).hexdigest() != json.loads(approval.read_bytes())["xcodegenSHA256"]:
    sys.exit("Tool binary differs from approved receipt")
PY_TOOL

stage=early-graph-project-projection
"${offline[@]}" python3 "$hosted/verify_graph.py" projection .physical-audit-src/project.yml \
  .physical-audit-graph-only.yml > "$work/graph-project.log" 2>&1 || fail_guard graph-project-projection
printf 'enum GraphProbe {}\n' > .physical-audit-src/GraphProbe.swift
"${offline[@]}" "$XCODEGEN" generate --spec .physical-audit-graph-only.yml \
  >> "$work/graph-project.log" 2>&1 || fail_guard graph-project-generation
project=VoiceMatrixPhysicalAudit.xcodeproj
resolved="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$resolved")"
cp "$graph" "$resolved"
cmp "$graph" "$resolved" || fail_guard early-graph-seed-bytes
common_build=(-project "$project" -scheme VoiceMatrixPhysicalAudit -disableAutomaticPackageResolution
  -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation -clonedSourcePackagesDirPath "$work/SourcePackages"
  -derivedDataPath "$work/build")
stage=early-xcode-resolve
# Exact package declarations, no app model/resources. Check the real resolver before any donor or ASR payload.
if ! xcodebuild "${common_build[@]}" -resolvePackageDependencies > "$work/dependencies.log" 2>&1; then
  "${offline[@]}" python3 "$hosted/verify_graph.py" report "$resolved" || true
  fail_guard early-xcode-resolve
fi
stage=early-frozen-graph-byte-comparison
"${offline[@]}" python3 "$hosted/verify_graph.py" report "$resolved" || fail_guard early-frozen-graph-byte-comparison
cmp "$graph" "$resolved" || fail_guard early-frozen-graph-byte-comparison
mv "$project" "$work/graph-only.xcodeproj"
disk_guard 8388608 disk-after-early-dependencies-before-model-fetch

stage=single-immutable-baseline-acquisition
baseline="$work/original.ipa"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --max-filesize 1330407101 --max-time 900 \
  https://github.com/R347H4CK3R/Ghostline/releases/download/voicematrix-v0.4.13-build16/VoiceMatrix-0.4.13-build16.ipa -o "$baseline"
chmod 0400 "$baseline"
common=(--baseline "$baseline" --approval "$receipt" --approval-sha256 "$receipt_sha")
stage=verified-f5-and-diarization-baseline-subset
"${offline[@]}" python3 "$hosted/derive_baseline_models.py" "$baseline" "$work/models" > "$work/baseline.log" 2>&1
stage=single-replacement-asr-acquisition
# Exact reviewed 16 remote files 631,653,214 bytes; two original buffers and metadata local. No retries.
python3 probes/native-original-asr/stage_models.py --destination "$work/models/ParakeetASR" > "$work/asr.log" 2>&1
stage=pinned-python
mkdir -p "$work/sdk/wheels"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  --max-filesize 34524958 --max-time 240 \
  https://github.com/beeware/Python-Apple-support/releases/download/3.13-b18/Python-3.13-iOS-support.b18.tar.gz \
  -o "$work/sdk/Python-3.13-iOS-support.b18.tar.gz"
python3 -m pip --isolated --no-cache-dir download --index-url https://pypi.org/simple --require-hashes --no-deps --only-binary=:all: \
  -r tools/python-runtime/requirements-ios-resolver.txt --dest "$work/sdk/wheels" > "$work/wheels.log" 2>&1
stage=offline-verified-resource-staging
"${offline[@]}" python3 "$gate" stage "${common[@]}" --staged "$work/models" --sdk "$work/sdk" > "$work/stage.log" 2>&1
rm -rf -- "$work/models" "$work/sdk"
"${offline[@]}" python3 probes/mkv-f5-ios/generate.py .strict-f5-fixture > "$work/fixture.log" 2>&1
"${offline[@]}" python3 tools/create_diagnostic_collection.py >> "$work/fixture.log" 2>&1
cp .physical-audit-src/project.yml physical-audit-project.yml
"${offline[@]}" "$XCODEGEN" generate --spec physical-audit-project.yml > "$work/project.log" 2>&1

stage=full-project-frozen-graph-restore
mkdir -p "$(dirname "$resolved")"
cp "$graph" "$resolved"
"${offline[@]}" python3 "$hosted/verify_graph.py" report "$resolved" || fail_guard full-project-frozen-graph-restore
cmp "$graph" "$resolved" || fail_guard full-project-frozen-graph-restore
stage=exact-dependency-notices
"${offline[@]}" python3 tools/character_package.py notices --checkouts "$work/SourcePackages/checkouts" \
  --resolved "$graph" --resources .physical-audit-assets > "$work/notices.log" 2>&1
# The generated resource group folder tracks contents; retain the verified graph and record exact disk capacity gate.
disk_guard 6291456 disk-after-dependencies-before-compile
stage=native-device-build
if "${offline[@]}" xcodebuild "${common_build[@]}" -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build \
  > "$work/build.log" 2>&1; then
  :
else
  status=$?
  printf 'audit_arm64_build_diagnostic_stage=native-device-build\n'
  "${offline[@]}" python3 "$hosted/native_failure.py" "$status" "$work/build.log"
  exit "$status"
fi
cmp "$graph" "$resolved" || fail_guard post-build-frozen-graph-byte-comparison
stage=ephemeral-package-inspection
mkdir "$work/Payload"
# Same volume atomic move: no second full-sized app.
app="$work/Payload/VoiceMatrixPhysicalAudit.app"
mv "$work/build/Build/Products/Release-iphoneos/VoiceMatrixPhysicalAudit.app" "$app"
ipa="$work/audit.ipa"
"${offline[@]}" python3 tools/package_ipa.py "$work/Payload" "$ipa"
"${offline[@]}" python3 "$gate" inspect "${common[@]}" --app "$app" --ipa "$ipa" --fixture .strict-f5-fixture \
  > "$work/audit-proof.json" 2> "$work/inspect.log"
stage=allowlisted-results
"${offline[@]}" python3 "$hosted/report_metadata.py" "$work/audit-proof.json" "$expected_source" > "$work/reviewed-summary.json"
cat "$work/reviewed-summary.json"
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  cat "$work/reviewed-summary.json" >> "$GITHUB_STEP_SUMMARY"
fi
# Never transmit the local IPA, build logs, resources, or checkout. VM teardown removes generated staging.
