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
CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)
python3 - "$DEVICE" "$BUNDLE" "$CONTAINER" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys
import time

device, bundle, path = sys.argv[1:]
documents = Path(path) / "Documents"
guarded = documents / "guarded-inputs.json"
constructor = documents / "constructor-inputs.json"
returned = documents / "constructor-returned.json"
assert not any(p.exists() for p in (guarded, constructor, returned)), "Stale or unowned probe files"


def run(*args):
    return subprocess.run(["xcrun", "simctl", *args], capture_output=True, timeout=15, text=True)


def launch(flag):
    result = run("launch", "--terminate-running-process", device, bundle, flag)
    assert result.returncode == 0, f"Owned app could not start: {flag}"
    pid_line = re.fullmatch(re.escape(bundle) + r": ([1-9][0-9]*)", result.stdout.strip())
    assert pid_line, f"Launch did not identify the app process: {flag}"
    return int(pid_line.group(1))


def await_file(path, seconds):
    deadline = time.monotonic() + seconds
    while not path.exists() and time.monotonic() < deadline:
        time.sleep(.1)
    return path.exists()


def read_inputs(path, reproduce):
    assert await_file(path, 12), f"Owned app did not record {path.name}"
    contents = json.loads(path.read_text())
    assert set(contents) == {"hasDevice", "hasArchitecture", "hasName", "hasUTF8", "apple7", "reproduce"}
    assert all(type(v) is bool for v in contents.values())
    assert contents.pop("reproduce") is reproduce
    return contents


first_pid = launch("--guarded")
first = read_inputs(guarded, False)
second_pid = launch("--constructor")
assert second_pid != first_pid, "Constructor measurement did not restart owned process"
second = read_inputs(constructor, True)
assert first == second, "Metal capability differed between app processes"
proof = None
if await_file(returned, 4):
    proof = json.loads(returned.read_text())
    assert set(proof) == {"returned", "length"} and proof["returned"] is True
    assert type(proof["length"]) is int and 0 <= proof["length"] < 1024
# Do not treat an absent return marker as a symbolicated crash.
print(json.dumps({"processesDistinct": True, "matchingInputs": first,
                  "constructorReturnObserved": proof is not None,
                  "constructorStringLength": proof["length"] if proof else None,
                  "symbolicatedVoiceMatrixCrash": False}, sort_keys=True), flush=True)
run("terminate", device, bundle)
PY
