#!/bin/bash
# Existing standard macOS hosted runner only; no runner upgrades or billing changes.
set -euo pipefail
cd "$(dirname "$0")/.."
PROJECT_ROOT="$PWD"
[[ "$(uname -s)" == Darwin ]] || { echo 'Apple-native verification requires macOS/Xcode' >&2; exit 1; }
XCODEGEN="$PROJECT_ROOT/.tooling/xcodegen/bin/xcodegen"
[[ -x "$XCODEGEN" ]] || { echo 'Verified pinned XcodeGen missing' >&2; exit 1; }
python3 tools/prepare_python_runtime.py --destination Vendors/Python
python3 tools/test_python_runtime_package.py
"$XCODEGEN" generate --spec runtime-harness.yml
DEVICE=$(xcrun simctl list devices available -j | python3 tools/select_ios26_simulator.py)
xcodebuild -project PythonRuntimeHarness.xcodeproj -scheme VoiceMatrix -destination "platform=iOS Simulator,id=$DEVICE" -derivedDataPath native-runtime-build -resultBundlePath native-runtime-tests.xcresult test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES | tee native-runtime-tests.log
