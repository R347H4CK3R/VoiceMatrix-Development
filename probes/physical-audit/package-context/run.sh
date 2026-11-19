#!/bin/bash
# Local-only proposal. This test plans an iOS build; no model resources or full app build.
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1
guard() { printf 'audit_package_context_guard=%s\n' "$1" >&2; exit 1; }
[[ $# == 1 && $(uname -s) == Darwin && $(uname -m) == arm64 ]] || guard platform-or-arity
[[ ${AUDIT_PACKAGE_CONTEXT_REVIEWED:-} == exact-software-dependency-resolution-only ]] || guard activation-not-approved
xcodegen=$1
[[ $xcodegen == /* && -f $xcodegen && -x $xcodegen && ! -L $xcodegen ]] || guard xcodegen-tool
[[ $(shasum -a 256 "$xcodegen" | awk '{print $1}') == a450f63bdd650c280cfce0fef6c94dbb19c5bf8dc32811361fd5d2e912718503 ]] || guard exact-xcodegen
export DEVELOPER_DIR=/Applications/Xcode_26.6.app/Contents/Developer
[[ $(xcodebuild -version 2>/dev/null) == $'Xcode 26.6\nBuild version 17F113' ]] || guard exact-xcode
[[ $(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null) == 26.5 ]] || guard exact-iphoneos-sdk
[[ -x /usr/bin/sandbox-exec ]] || guard sandbox
source_root=$(git rev-parse --show-toplevel 2>/dev/null) || guard checkout
[[ $(git rev-parse 9fb76c75c3cdb85a1a4f52bfab1d1b38eaba2b5d^{tree} 2>/dev/null) == f2d324917f21d071a52744cc892c41659533b91b ]] || guard diagnosed-build
git diff --quiet 9fb76c75c3cdb85a1a4f52bfab1d1b38eaba2b5d HEAD -- VoiceMatrix Vendors project.yml tools tests python-resolver || guard app-or-vendor-drift
git diff --quiet && git diff --cached --quiet || guard dirty-checkout
git_head=$(git rev-parse HEAD)
scratch=$(mktemp -d "${RUNNER_TEMP:-/tmp}/vm-audit-package-context.XXXXXX") || guard owned-scratch
workspace="$scratch/source"
cleanup() {
  local code=$?
  trap - EXIT
  cd "$source_root"
  if [[ -d $workspace ]]; then
    git worktree remove --force "$workspace" > "$scratch/cleanup.log" 2>&1 || true
  fi
  rm -rf -- "$scratch"
  exit "$code"
}
trap cleanup EXIT
git worktree add --detach "$workspace" "$git_head" > "$scratch/worktree.log" 2>&1 || guard worktree
cd "$workspace"

offline=(/usr/bin/sandbox-exec -p '(version 1)(allow default)(deny network*)')
hosted=probes/physical-audit/hosted
probe=probes/physical-audit/package-context
graph="$scratch/canonical-Package.resolved"
"${offline[@]}" python3 "$hosted/verify_graph.py" seed "$graph" > "$scratch/graph.log" 2>&1 || guard canonical-graph-seed
"${offline[@]}" python3 probes/physical-audit/prepare.py .physical-audit-src > "$scratch/prep.log" 2>&1 || guard exact-projection-source
"${offline[@]}" python3 "$hosted/verify_graph.py" projection .physical-audit-src/project.yml .only-packages.yml >> "$scratch/prep.log" 2>&1 || guard package-projection
printf 'enum GraphProbe {}\n' > .physical-audit-src/GraphProbe.swift
"${offline[@]}" "$xcodegen" generate --spec .only-packages.yml > "$scratch/generate-a.log" 2>&1 || guard generate-a
project=VoiceMatrixPhysicalAudit.xcodeproj
resolved="$project/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
store="$scratch/SourcePackages"
mkdir -p "$(dirname "$resolved")"
cp "$graph" "$resolved"
cmp -s "$graph" "$resolved" || guard seed-graph
common=(-project "$project" -scheme VoiceMatrixPhysicalAudit -disableAutomaticPackageResolution
        -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation
        -clonedSourcePackagesDirPath "$store" -derivedDataPath "$scratch/DerivedData"
        -configuration Release -sdk iphoneos -destination 'generic/platform=iOS'
        CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ONLY_ACTIVE_ARCH=YES)

report_failure() {
  printf 'audit_package_context_failed_phase=%s\n' "$1"
  "${offline[@]}" python3 "$hosted/native_failure.py" "$2" "$3"
  exit "$2"
}
# Only this already-reviewed dependency materialization is allowed to reach the network.
# No compiler target, changed graph, credentials, models, archive/donor, or upload.
if xcodebuild "${common[@]}" -resolvePackageDependencies > "$scratch/resolve.log" 2>&1; then
  :
else
  report_failure materialize-ios-frozen-graph "$?" "$scratch/resolve.log"
fi
cmp -s "$graph" "$resolved" || guard graph-changed-on-ios-materialization
snapshot() {
  local name=$1
  if "${offline[@]}" python3 "$probe/materialization.py" "$store" > "$scratch/$name.json"; then
    printf 'audit_package_context_phase=%s\n' "$name"
    cat "$scratch/$name.json"
  else
    printf 'audit_package_context_failed_phase=%s\n' "$name"
    cat "$scratch/$name.json"
    exit 1
  fi
}
snapshot materialization-before-offline
if "${offline[@]}" xcodebuild "${common[@]}" -showBuildSettings > "$scratch/offline-a.log" 2>&1; then
  printf 'audit_package_context_phase=offline-before-regeneration-pass\n'
else
  report_failure offline-before-regeneration "$?" "$scratch/offline-a.log"
fi
cmp -s "$graph" "$resolved" || guard graph-changed-before-regeneration
snapshot materialization-after-a

# Reproduce the prior handoff: move project away and generate into same absolute path.
# Deliberately perturb a no-op source entry, preserving the exact SwiftPM dependency declarations.
mv "$project" "$scratch/FirstGraph.xcodeproj" || guard preserve-a-project
printf 'enum GraphProbeExtra {}\n' > .physical-audit-src/GraphProbeExtra.swift
python3 - <<'PY'
from pathlib import Path
p=Path(".only-packages.yml")
s=p.read_text()
line="    - .physical-audit-src/GraphProbe.swift\n"
if s.count(line)!=1: raise SystemExit("project-source-anchor")
Path(".regenerated-packages.yml").write_text(s.replace(line,line+"    - .physical-audit-src/GraphProbeExtra.swift\n"),encoding="utf-8")
PY
"${offline[@]}" "$xcodegen" generate --spec .regenerated-packages.yml > "$scratch/generate-b.log" 2>&1 || guard generate-b
mkdir -p "$(dirname "$resolved")"
cp "$graph" "$resolved"
cmp -s "$graph" "$resolved" || guard graph-changed-on-restore
snapshot materialization-before-b
if "${offline[@]}" xcodebuild "${common[@]}" -showBuildSettings > "$scratch/offline-b.log" 2>&1; then
  printf 'audit_package_context_phase=offline-after-regeneration-pass\n'
else
  report_failure offline-after-regeneration "$?" "$scratch/offline-b.log"
fi
cmp -s "$graph" "$resolved" || guard graph-changed-after-regeneration
snapshot materialization-after-b

"${offline[@]}" python3 - "$scratch" <<'PY'
import json,sys
from pathlib import Path
root=Path(sys.argv[1])
labels=("materialization-before-offline","materialization-after-a","materialization-before-b","materialization-after-b")
rows=[json.loads((root/(label+".json")).read_bytes()) for label in labels]
same=all(item["binaries"]==rows[0]["binaries"] for item in rows)
state=all(item["workspaceStateSHA256"]==rows[0]["workspaceStateSHA256"] for item in rows)
print(json.dumps({"knownDeviceSliceInventoryStable":same,"workspaceStateBytesStable":state,
                  "canonicalGraphStable":True,"plannedOfflineBeforeAndAfterRegeneration":True,
                  "fullAppBuild":False,"modelPayloadFetched":False},sort_keys=True))
if not same: sys.exit(1)
PY
