#!/usr/bin/env bash
set -euo pipefail
test "$#" = 1
DEVICE=$1
[[ $DEVICE =~ ^[0-9A-Fa-f-]{36}$ ]]
SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/MetalArchProbe.app"
BUNDLE=org.voicematrix.metal-arch-probe
mkdir "$APP"
cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.voicematrix.metal-arch-probe</string>
<key>CFBundleExecutable</key><string>MetalArchProbe</string>
<key>CFBundleName</key><string>MetalArchProbe</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>MinimumOSVersion</key><string>26.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>CFBundleSupportedPlatforms</key><array><string>iPhoneSimulator</string></array>
</dict></plist>
PLIST
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun --sdk iphonesimulator clang++ -std=c++20 -target arm64-apple-ios26.0-simulator -isysroot "$SDK" -fobjc-arc -g \
    -framework Foundation -framework Metal -framework UIKit "$SOURCE/main.mm" -o "$APP/MetalArchProbe"
xcrun simctl bootstatus "$DEVICE" -b >&2
xcrun simctl install "$DEVICE" "$APP" >&2
python3 - "$DEVICE" "$BUNDLE" <<'PY'
import json, re, subprocess, sys
device, bundle = sys.argv[1:]
result = {}
command = ["xcrun", "simctl", "launch", "--console", "--terminate-running-process", device, bundle]
pattern = (r"METAL_ARCH_PROBE device=([01]) architecture=([01]) name=([01]) "
           r"utf8=([01]) apple7=([01]) reproduce=([01])")
for label, args in (("guarded", []), ("constructor", ["--reproduce"])):
    run = subprocess.run(command + args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30, text=True)
    match = re.search(pattern, run.stdout)
    assert match is not None, (label, "No measurement received", run.returncode)
    values = list(map(int, match.groups()))
    assert values[-1] == (label == "constructor")
    result[label] = dict(zip(("hasDevice", "hasArchitecture", "hasName", "hasUTF8", "apple7"),
                             map(bool, values[:-1])))
    result[label].update(constructorReturned="METAL_ARCH_CONSTRUCTOR_RETURNED " in run.stdout,
                         nullStringAssertion="basic_string(const char*) detected nullptr" in run.stdout,
                         launchExit=run.returncode)
assert all(result["guarded"][key] == result["constructor"][key] for key in
           ("hasDevice", "hasArchitecture", "hasName", "hasUTF8", "apple7"))
print(json.dumps(result, sort_keys=True), flush=True)
PY
