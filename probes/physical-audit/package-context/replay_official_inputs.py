"""Replay official local pinned ZIPs. Never fetch or execute any archive member."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import shutil
import stat
import sys
import tempfile
import zipfile

from materialization import PINS, inspect

INPUTS = (("onnxruntime", 52138597), ("NemoTextProcessing", 87267919))


def replay(paths):
    if len(paths) != len(INPUTS):
        raise ValueError("Provide exact local ONNX and Nemo ZIPs")
    with tempfile.TemporaryDirectory(prefix="vm-binary-structure-proof-") as tmp:
        store = Path(tmp) / "SourcePackages"
        rows = []
        for archive_path, (target, size) in zip(paths, INPUTS):
            pin = PINS[target]
            if archive_path.is_symlink() or archive_path.stat().st_size != size:
                raise ValueError("Official ZIP size differs")
            with archive_path.open("rb") as handle:
                if hashlib.file_digest(handle, "sha256").hexdigest() != pin["sha"]:
                    raise ValueError("Official ZIP pin differs")
            with zipfile.ZipFile(archive_path) as z:
                manifests = [i for i in z.infolist()
                             if i.filename.endswith(".xcframework/Info.plist")
                             and not i.filename.startswith("__MACOSX/")]
                if len(manifests) != 1 or manifests[0].file_size > 262144:
                    raise ValueError("Unexpected official XCFramework plist")
                manifest = manifests[0]
                prefix = manifest.filename.removesuffix("Info.plist")
                folder = store / "artifacts" / pin["identity"] / PurePosixPath(prefix).name
                folder.mkdir(parents=True)
                raw = z.read(manifest)
                (folder / "Info.plist").write_bytes(raw)
                rows_ios = [p for p in plistlib.loads(raw)["AvailableLibraries"]
                            if p["SupportedPlatform"] == "ios" and not p.get("SupportedPlatformVariant")
                            and "arm64" in p["SupportedArchitectures"]]
                if len(rows_ios) != 1:
                    raise ValueError("Expected one physical iOS arm64 slice")
                chosen = prefix + rows_ios[0]["LibraryIdentifier"] + "/"
                total = 0
                for item in z.infolist():
                    if not item.filename.startswith(chosen) or item.is_dir():
                        continue
                    rel = PurePosixPath(item.filename.removeprefix(prefix))
                    total += item.file_size
                    if (rel.is_absolute() or ".." in rel.parts or "\\" in item.filename
                            or stat.S_ISLNK(item.external_attr >> 16) or total > 512 * 1024 * 1024):
                        raise ValueError("Unsafe physical slice")
                    out = folder.joinpath(*rel.parts)
                    out.parent.mkdir(parents=True, exist_ok=True)
                    with z.open(item) as src, out.open("xb") as dst:
                        shutil.copyfileobj(src, dst, 1048576)
                rows.append({"targetName": target, "packageRef": {"identity": pin["identity"]},
                             "source": {"type": "remote", "url": pin["url"], "checksum": pin["sha"]},
                             "path": str(folder)})
        (store / "workspace-state.json").write_text(json.dumps({"object": {"artifacts": rows}}, sort_keys=True))
        result = inspect(store)
        # This replay uses synthetic registry state for known direct ZIP bytes,
        # not observed state from an actual xcodebuild process.
        result.pop("workspaceStateSHA256", None)
        result["officialZipBytesVerified"] = True
        result["archiveMembersExecuted"] = False
        return result


if __name__ == "__main__":
    output = replay(list(map(Path, sys.argv[1:])))
    print(json.dumps(output, sort_keys=True))
    if not output["requiredValidated"]:
        sys.exit(1)
