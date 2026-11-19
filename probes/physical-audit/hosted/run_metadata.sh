#!/bin/bash
# Hosted macOS build, deliberately not invoked by any installed workflow.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
root=$(git rev-parse --show-toplevel)
cd "$root"
[[ ${GITHUB_ACTIONS:-} == true && ${GITHUB_REPOSITORY:-} == R347H4CK3R/VoiceMatrix-Development ]]
[[ ${GITHUB_REF:-} == refs/heads/verification/physical-audit-arm64 && ${GITHUB_RUN_ATTEMPT:-} == 1 ]]
[[ $(uname -s) == Darwin && $(uname -m) == arm64 && $# == 4 ]]
expected_source=$1 expected_tree=$2 receipt=$3 receipt_sha=$4
[[ $expected_source =~ ^[a-f0-9]{40}$ && $expected_tree =~ ^[a-f0-9]{40}$ && $receipt_sha =~ ^[a-f0-9]{64}$ ]]
[[ ${GITHUB_SHA:-} == "$expected_source" && $(git rev-parse HEAD) == "$expected_source" ]]
[[ $(git rev-parse HEAD^{tree}) == "$expected_tree" ]]
[[ $(git rev-parse 42da8f3ed18ca1c0f1462032db5dc05ce77362a1^{tree}) == 24e298cb887b1a6bf19c177c0733e06f5a474bfc ]]
[[ $(git rev-parse 4ed344a8bb859e841c35041f3f07b9510a930492^{tree}) == 53e26cfe17017df02c2c6fdc1e63a8c0d6f3ba37 ]]
git diff --quiet && git diff --cached --quiet
[[ -z $(git ls-files --others --exclude-standard) ]]
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
[[ $(xcodebuild -version) == $'Xcode 26.6\nBuild version 17F113' ]]
[[ $(xcrun --sdk iphoneos --show-sdk-version) == 26.5 ]]
command -v ffmpeg >/dev/null
command -v ffprobe >/dev/null

# Anticipated max data before compile: baseline 1.331GB, model+tools 1.40GB,
# one scratch app+archive ~3GB; require surplus for source dependency/build layers.
disk_kib() { df -Pk "$root" | awk 'END { print $4 }'; }
[[ $(disk_kib) -ge 10485760 ]]  # 10 GiB actual upfront; fail before any large download.
work=$(mktemp -d "$root/.audit-transient.XXXXXX")
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
graph="$root/tests/fixtures/build17-original-Package.resolved"
graphsha=ff9369012927524e241f0cf3bcca1a72177947e02ef7933beef716377c87de72
[[ $(shasum -a 256 "$graph" | awk '{print $1}') == "$graphsha" ]]
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
if r["xcodeVersion"] != "Xcode 26.6" or r["iphoneOSSDK"] != "26.5":
    sys.exit("Clearance receipt does not bind this toolchain")
PY_RECEIPT

offline=(/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)')
stage=source-tooling
# Verify clean exact runtime before the local ephemeral build mutates ignored directories.
"${offline[@]}" python3 probes/physical-audit/prepare.py .physical-audit-src > "$work/source.log" 2>&1
"${offline[@]}" python3 tools/vendored_fluid.py >> "$work/source.log" 2>&1
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

stage=exact-dependency-graph
project=VoiceMatrixPhysicalAudit.xcodeproj
resolved="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
mkdir -p "$(dirname "$resolved")"
cp "$graph" "$resolved"
common_build=(-project "$project" -scheme VoiceMatrixPhysicalAudit -disableAutomaticPackageResolution
  -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation -clonedSourcePackagesDirPath "$work/SourcePackages"
  -derivedDataPath "$work/build")
# Resolve the frozen source-only pins before compilation; no resolution during the offline compile.
xcodebuild "${common_build[@]}" -resolvePackageDependencies > "$work/dependencies.log" 2>&1
cmp "$graph" "$resolved"
"${offline[@]}" python3 tools/character_package.py notices --checkouts "$work/SourcePackages/checkouts" \
  --resolved "$graph" --resources .physical-audit-assets > "$work/notices.log" 2>&1
# The generated resource group folder tracks contents; retain the verified graph and record exact disk capacity gate.
[[ $(disk_kib) -ge 6291456 ]]  # 6 GiB actual after inputs/packages; never escalate to paid runners.
stage=native-device-build
"${offline[@]}" xcodebuild "${common_build[@]}" -configuration Release -sdk iphoneos \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build \
  > "$work/build.log" 2>&1
cmp "$graph" "$resolved"
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
