"""Fixed metadata from validated SwiftPM artifact state and local device slice; no raw state or URLs."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import struct
import sys

PINS = {
    "onnxruntime": {"identity": "onnxruntime", "required": True, "label": "onnx",
                    "url": "https://download.onnxruntime.ai/pod-archive-onnxruntime-c-1.24.2.zip",
                    "sha": "f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54",
                    "binary_sha": "6cd9d2a7e174f2de317861331bc4454729bab187da92562f8163dee1be8cb55a"},
    "NemoTextProcessing": {"identity": "fluidaudio", "required": True, "label": "fluid-nemo",
                           "url": "https://github.com/FluidInference/text-processing-rs/releases/download/v0.3.1/NemoTextProcessing.xcframework.zip",
                           "sha": "5fa8c10d4ec26c1bb2413125f351a7222a4c68a23b74476680fbada7e26fc6aa",
                           "binary_sha": "c55443e6c8a49c836f09a96ef5fd4d0f927d791de0ab17106cd74f5886ef393f",
                           "allow_legacy": True},
    "CSpeechCore": {"identity": "speech-swift", "required": False, "label": "speechswift-optional",
                    "url": "https://github.com/soniqo/speech-core/releases/download/v0.0.14/SpeechCore.xcframework.zip",
                    "sha": "68517f044b98a54e8779dccab850ae383ad5a5595471430c9e10118abec345cd"},
}
STATE_LIMIT = 1048576
FILE_CAP = 4096
BYTE_CAP = 512 * 1024 * 1024


def bounded_file(path, maximum):
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= maximum:
        raise ValueError
    return path.read_bytes()


def one_part(value):
    return isinstance(value, str) and value not in ("", ".", "..") and len(value) <= 256 and "/" not in value and "\\" not in value


def files_digest(path):
    records = []
    total = 0
    for item in sorted(path.rglob("*")):
        if len(records) >= FILE_CAP or item.is_symlink():
            raise ValueError
        if item.is_dir():
            continue
        if not item.is_file():
            raise ValueError
        length = item.stat().st_size
        total += length
        if total > BYTE_CAP:
            raise ValueError
        with item.open("rb") as handle:
            sha = hashlib.file_digest(handle, "sha256").hexdigest()
        records.append([item.relative_to(path).as_posix(), length, sha])
    if not records or total == 0:
        raise ValueError
    return hashlib.sha256(json.dumps(records, separators=(",", ":")).encode()).hexdigest()


def ios_macho(handle, start, size, legacy=False):
    if size < 32:
        return None
    handle.seek(start)
    head = handle.read(32)
    if len(head) != 32 or head[:4] != b"\xcf\xfa\xed\xfe":
        return None
    _, cpu, _, kind, count, length, _, _ = struct.unpack("<8I", head)
    if cpu != 0x100000C or kind not in (1, 2, 6) or not 1 <= count <= 512 or not 8 <= length <= min(size-32, 1048576):
        return False
    block = handle.read(length)
    cursor = 0
    found, old_ios = [], []
    for _ in range(count):
        if cursor + 8 > len(block):
            return False
        cmd, span = struct.unpack_from("<2I", block, cursor)
        if span < 8 or span % 8 or cursor + span > len(block):
            return False
        if cmd == 0x32:
            if span < 24:
                return False
            platform, _, _, ntools = struct.unpack_from("<4I", block, cursor + 8)
            if span != 24 + ntools * 8:
                return False
            found.append(platform)
        elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS, older than LC_BUILD_VERSION.
            if span != 16:
                return False
            old_ios.append(struct.unpack_from("<2I", block, cursor + 8))
        elif cmd in (0x24, 0x2F, 0x30):  # conflicting legacy macOS/tvOS/watchOS
            return False
        cursor += span
    if cursor != len(block):
        return False
    if found:
        return found == [2] and not old_ios
    # The one exact reviewed Rust device archive has only this legacy encoding.
    # Authorization is decided above this reader by SHA of the complete archive.
    return legacy and kind == 1 and old_ios in ([(0x000A0000, 0)], [(0x000A0000, 0x001A0200)])


def ios_payload(handle, start, size, legacy=False, require_ar=False):
    end = start + size
    handle.seek(start)
    signature = handle.read(8)
    if signature != b"!<arch>\n":
        return not require_ar and ios_macho(handle, start, size, legacy) is True
    position, seen = start + 8, 0
    for _ in range(65536):
        if position == end:
            return bool(seen)
        if position + 60 > end:
            return False
        handle.seek(position)
        h = handle.read(60)
        if h[-2:] != b"`\n":
            return False
        try:
            length = int(h[48:58])
            name = h[:16].decode("ascii").strip()
            extended = int(name[3:]) if name.startswith("#1/") else 0
        except (ValueError, UnicodeDecodeError):
            return False
        if not 0 <= extended <= min(length, 4096) or position + 60 + length > end:
            return False
        if extended:
            name = handle.read(extended).rstrip(b"\x00").decode("ascii", errors="replace")
        if name not in ("/", "//", "/SYM64/", "__.SYMDEF", "__.SYMDEF SORTED", "__.SYMDEF_64", "__.SYMDEF_64 SORTED"):
            if ios_macho(handle, position + 60 + extended, length - extended, legacy) is not True:
                return False
            seen += 1
        position += 60 + length + length % 2
    return False


def ios_device_binary(path, legacy_sha=None):
    size = path.stat().st_size
    if not 0 < size <= BYTE_CAP:
        return False
    with path.open("rb") as handle:
        legacy = bool(legacy_sha and hashlib.file_digest(handle, "sha256").hexdigest() == legacy_sha)
        handle.seek(0)
        head = handle.read(28)
        if head[:4] != b"\xca\xfe\xba\xbe":
            return ios_payload(handle, 0, size, legacy=legacy)
        # Exact accepted universal shape: big-endian FAT32, one ARM64 ALL
        # architecture, exactly bounded/aligned payload and no extra slices.
        if len(head) != 28:
            return False
        _, count, cpu, subtype, offset, length, alignment = struct.unpack(">7I", head)
        if ((count, cpu, subtype) != (1, 0x100000C, 0) or alignment > 20
                or not len(head) <= offset <= len(head) + 4096 or offset % (1 << alignment)
                or length == 0 or offset + length != size):
            return False
        if any(handle.read(offset - len(head))):
            return False  # Fat header padding is not an untracked member or slice.
        return ios_payload(handle, offset, length, require_ar=True)


def check_entry(row, pin, own):
    try:
        if (row["packageRef"]["identity"].casefold() != pin["identity"]
                or any(row["source"].get(key) != val for key, val in
                       {"type": "remote", "url": pin["url"], "checksum": pin["sha"]}.items())):
            return {"status": "state-pin-mismatch"}
        path = Path(row["path"])
        if (not path.is_absolute() or not path.resolve().is_relative_to(own) or path.is_symlink()):
            return {"status": "outside-owned-artifacts"}
        # Normalize system aliases above the package-store root, but do not
        # accept symlink hops within the artifact tree itself.
        cursor = path
        while True:
            if cursor.is_symlink():
                return {"status": "outside-owned-artifacts"}
            if cursor.resolve() == own:
                break
            if cursor == cursor.parent:
                return {"status": "outside-owned-artifacts"}
            cursor = cursor.parent
        if not path.is_dir() or path.suffix != ".xcframework":
            return {"status": "missing-extracted-xcframework"}
        info = plistlib.loads(bounded_file(path / "Info.plist", 262144))
        matches = [part for part in info["AvailableLibraries"]
                   if part["SupportedPlatform"] == "ios" and not part.get("SupportedPlatformVariant")
                   and "arm64" in part["SupportedArchitectures"]]
        if len(matches) != 1:
            return {"status": "missing-ios-device-slice"}
        entry = matches[0]
        ident, lib = entry["LibraryIdentifier"], entry["LibraryPath"]
        if not one_part(ident) or not one_part(lib):
            return {"status": "invalid-ios-slice-layout"}
        slice_root = path / ident
        library = slice_root / lib
        if slice_root.is_symlink() or library.is_symlink() or not slice_root.is_dir():
            return {"status": "invalid-ios-slice-layout"}
        if library.suffix == ".framework":
            # iOS frameworks are flat; validate the declared executable rather than a macOS alias.
            f_info = plistlib.loads(bounded_file(library / "Info.plist", 262144))
            executable = f_info["CFBundleExecutable"]
            if not one_part(executable):
                return {"status": "invalid-ios-slice-layout"}
            binary = library / executable
        else:
            binary = library
        if binary.is_symlink() or not binary.is_file() or not binary.stat().st_size:
            return {"status": "missing-ios-device-slice"}
        binary_sha = pin.get("binary_sha")
        if not ios_device_binary(binary, legacy_sha=binary_sha if pin.get("allow_legacy") else None):
            return {"status": "invalid-ios-device-binary"}
        if binary_sha is not None:
            with binary.open("rb") as handle:
                if hashlib.file_digest(handle, "sha256").hexdigest() != binary_sha:
                    return {"status": "device-binary-pin-mismatch"}
        return {"status": "validated-state-and-ios-slice", "iosSliceSHA256": files_digest(slice_root)}
    except (OSError, TypeError, KeyError, ValueError, AttributeError, RuntimeError, plistlib.InvalidFileException):
        return {"status": "invalid-materialization"}


def inspect(package_store):
    path = package_store / "workspace-state.json"
    try:
        raw = bounded_file(path, STATE_LIMIT)
        state = json.loads(raw)
        rows = state["object"]["artifacts"]
        if not isinstance(rows, list) or len(rows) > 128 or not all(isinstance(x, dict) for x in rows):
            raise ValueError
    except (OSError, TypeError, ValueError, KeyError):
        return {"requiredValidated": False, "status": "missing-or-unsupported-workspace-state", "binaries": {
            p["label"]: {"status": "workspace-state-unavailable"} for p in PINS.values()}}
    keys = set(PINS)
    extras = sum(not isinstance(row.get("targetName"), str) or row["targetName"] not in keys for row in rows)
    result = {}
    artifacts = package_store / "artifacts"
    if package_store.is_symlink() or artifacts.is_symlink() or not artifacts.resolve().is_relative_to(package_store.resolve()):
        return {"requiredValidated": False, "status": "unowned-artifact-store", "binaries": {
            p["label"]: {"status": "artifact-store-unowned"} for p in PINS.values()}}
    own = artifacts.resolve()
    for target, pin in PINS.items():
        named = [r for r in rows if r.get("targetName") == target]
        if len(named) == 1:
            result[pin["label"]] = check_entry(named[0], pin, own)
        elif named:
            result[pin["label"]] = {"status": "duplicate-materialization"}
        else:
            result[pin["label"]] = {"status": "missing-materialization" if pin["required"] else "not-selected"}
    passed = not extras and all(result[p["label"]]["status"] in (
        ("validated-state-and-ios-slice",) if p["required"] else ("validated-state-and-ios-slice", "not-selected"))
        for p in PINS.values())
    return {"requiredValidated": passed, "workspaceStateSHA256": hashlib.sha256(raw).hexdigest(),
            "unexpectedBinaryCount": extras, "binaries": result}


if __name__ == "__main__":
    summary = inspect(Path(sys.argv[1]))
    print(json.dumps(summary, sort_keys=True))
    if not summary["requiredValidated"]:
        sys.exit(1)
