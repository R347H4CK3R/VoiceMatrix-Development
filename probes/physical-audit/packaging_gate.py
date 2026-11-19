"""Inspect only local pre-approved bytes for the noncommercial hardware audit. No network."""
import argparse
from datetime import date
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import shutil
import stat
import struct
import subprocess
import sys
import unicodedata
import zipfile

ROOT = Path(__file__).resolve().parents[2]
RUNTIME = "42da8f3ed18ca1c0f1462032db5dc05ce77362a1"
AUDIT_ID = "com.voicematrix.physicalaudit"
BASELINE = {"size": 1330407101, "sha256": "04d199d356a5fde59101d3909a35abf05e8dd1129141e0add66e1e45006c5d11"}
LOCKS = {
    "ParakeetASR": ("probes/native-original-asr/resource-lock.json", "f58c59e24e41e17f701d7b2b7fc4aa45343c232a2119fb6540357f676a6416ce"),
    "Diarization": ("tools/diarization-resource-lock.json", "137ad0aba1483d0ba3c74cb5380ab05f5cd76a5eb47aa69b9de41c353315e7e0"),
    "F5TTS": ("tools/f5-listening-lock.json", "e51680c87462bb26433613fe61f7da735c59ab770020f5705a6159cda78bdb70"),
}
F5_NOTICES = ("F5-CC-BY-NC-4.0.txt", "speech-swift-APACHE-2.0.txt", "ATTRIBUTION.txt",
              "pypinyin-MIT.txt", "jieba-MIT.txt", "vocos-MIT.txt")
SDK = "Python-3.13-iOS-support.b18.tar.gz"
SDK_SHA = "d06acf2a9c7964a8689566353a0e707402eff822037de5e29ba0e16040f7047d"
GRAPH_SHA = "ff9369012927524e241f0cf3bcca1a72177947e02ef7933beef716377c87de72"
PYTHON_INSPECTOR_SHA = "f947b8689270aadb58d38a207396b3f97db7ec1c348747b7f48495219629e49f"
PREFIX = "Payload/VoiceMatrixPhysicalAudit.app/"


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def digest(path):
    require(path.is_file() and not path.is_symlink(), "Expected local regular file")
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def identity(path):
    return {"size": path.stat().st_size, "sha256": digest(path)}


def exact_tree(root, expected):
    require(root.is_dir() and not root.is_symlink(), "Expected separate model directory")
    files = {}
    for path in root.rglob("*"):
        require(not path.is_symlink(), "Refusing any symbolic link in resources")
        if path.is_dir():
            continue
        files[path.relative_to(root).as_posix()] = path
    require(set(files) == set(expected), "Unlisted or missing resource file")
    for name, path in files.items():
        require(identity(path) == expected[name], "Resource differs from pinned check: " + name)


def models(root):
    entries = {}
    for name, (location, sha) in LOCKS.items():
        path = root / location
        require(digest(path) == sha, "Model manifest differs from reviewed source")
        lock = json.loads(path.read_bytes())
        entries[name] = lock if name == "F5TTS" else {
            key: {k: row[k] for k in ("size", "sha256")} for key, row in lock["files"].items()
        }
    return entries


def required_receipt():
    return {"schemaVersion": 1, "scope": "private-noncommercial-hardware-audit-only",
            "runtimeRevision": RUNTIME, "baselineIPA": BASELINE,
            "modelLocks": {key: sha for key, (_, sha) in LOCKS.items()},
            "noFurtherDistribution": True, "noPersonalRecordings": True}


def require_receipt(receipt):
    """The receipt is an operator-reviewed assumption, not automatic license authorization."""
    required = required_receipt()
    binding = {"approvedBy", "approvalDateUTC", "graphSHA256", "xcodegenSHA256", "xcodeVersion", "iphoneOSSDK"}
    require(set(receipt) == set(required) | binding and all(receipt[key] == val for key, val in required.items()),
            "Missing exact scoped clearance record")
    require(isinstance(receipt["approvedBy"], str) and 1 <= len(receipt["approvedBy"].strip()) <= 128,
            "Review identity missing")
    require(date.fromisoformat(receipt["approvalDateUTC"]).isoformat() == receipt["approvalDateUTC"],
            "Approval date must be a canonical UTC date")
    require(receipt["graphSHA256"] == GRAPH_SHA and re.fullmatch("[a-f0-9]{64}", receipt["xcodegenSHA256"]),
            "Approval must bind exact tools and dependency graph")
    require(re.fullmatch(r"Xcode [0-9]+(?:\.[0-9]+){1,2}", receipt["xcodeVersion"])
            and re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,2}", receipt["iphoneOSSDK"]),
            "Approval must bind the compiler and device SDK")


def staged_model_inventories(root, model_root, include_dependencies=False):
    result = models(root)
    for name in ("ParakeetASR", "Diarization"):
        result[name]["resource-lock.json"] = identity(root / LOCKS[name][0])
    exact = result["F5TTS"]
    for name in F5_NOTICES:
        exact["Notices/" + name] = identity(root / "tools/listening_licenses" / name)
    engine = model_root / "F5TTS/voicematrix-engine.json"
    require(engine.is_file() and not engine.is_symlink() and 1 <= engine.stat().st_size <= 65536,
            "Missing or oversized F5 engine manifest")
    proof = json.loads(engine.read_bytes())
    model_files = {key: val for key, val in exact.items() if not key.startswith("Notices/")}
    require(proof == {"schemaVersion": 1, "engine": "F5TTS_v1_Base",
        "runtimeRevision": "a57702e6f523fa36ac5532d2bdc5f35f701a052c",
        "modelRepository": "aufklarer/F5TTS-v1-Base-MLX-fp16",
        "modelRevision": "685e88161a2841a5f102a6f8094613ba7131e350",
        "files": [dict(path=name, **entry) for name, entry in sorted(model_files.items())]},
        "Unexpected F5 engine manifest")
    exact["voicematrix-engine.json"] = identity(engine)
    if include_dependencies:
        notice_manifest = model_root / "F5TTS/dependency-notices.json"
        require(notice_manifest.stat().st_size <= 4_000_000, "Oversized dependency notice manifest")
        manifest = json.loads(notice_manifest.read_bytes())
        require(manifest["schemaVersion"] == 1 and len(manifest["files"]) > 2, "Missing dependency notice proof")
        require(manifest["files"]["fluid-audio-vendored/inventory.json"] ==
                identity(root / "Vendors/FluidAudio.inventory.json"), "Vendor inventory notice differs")
        require(manifest["files"]["fluid-audio-vendored/NOTICE-VoiceMatrix.txt"] ==
                identity(root / "Vendors/FluidAudio/NOTICE-VoiceMatrix.txt"), "Vendor source notice differs")
        exact["dependency-notices.json"] = identity(notice_manifest)
        exact.update({"DependencyNotices/" + name: pin for name, pin in manifest["files"].items()})
    for name, expected in result.items():
        exact_tree(model_root / name, expected)
    return result


def approved_notices(root, target):
    asr = target / "ParakeetNotices"
    dia = target / "DiarizationNotices"
    asr.mkdir()
    dia.mkdir()
    original = root / "VoiceMatrix/Resources/ParakeetNotices"
    sources = {"ATTRIBUTION.txt": root / "probes/native-original-asr/NOTICE.txt",
               "FRONTEND-APACHE-2.0.txt": root / "docs/asr-original-frontend/LICENSE",
               "FRONTEND-README.txt": root / "docs/asr-original-frontend/README.md",
               "CC-BY-4.0.txt": original / "CC-BY-4.0.txt",
               "FluidAudio-APACHE-2.0.txt": original / "FluidAudio-APACHE-2.0.txt"}
    for name, path in sources.items():
        shutil.copyfile(path, asr / name)
    for name, path in {"CC-BY-4.0.txt": original / "CC-BY-4.0.txt",
                       "FluidAudio-APACHE-2.0.txt": original / "FluidAudio-APACHE-2.0.txt"}.items():
        shutil.copyfile(path, dia / name)
    (dia / "ATTRIBUTION.txt").write_text(
        "FluidInference speaker-diarization-coreml, pinned df2625ac79a7ac6b65ad868fee6d80f320da4232.\n"
        "https://huggingface.co/FluidInference/speaker-diarization-coreml/tree/df2625ac79a7ac6b65ad868fee6d80f320da4232\n"
        "CC BY 4.0 compiled model bytes unchanged; historical conversion is unverified.\n", encoding="utf-8")
    shutil.copyfile(root / "Vendors/FluidAudio/NOTICE-VoiceMatrix.txt",
                    asr / "FluidAudio-MODIFICATIONS.txt")


def stage(root, source, destination, sdk_root):
    inventories = staged_model_inventories(root, source)
    require(set(item.name for item in source.iterdir()) == set(inventories), "Unexpected staged model root")
    destination.mkdir(exist_ok=False)
    for name, rows in inventories.items():
        shutil.copytree(source / name, destination / name)
        exact_tree(destination / name, rows)
    approved_notices(root, destination)
    stage_python(root, sdk_root)


def stage_python(root, sdk_root):
    sdk = sdk_root / SDK
    require(digest(sdk) == SDK_SHA, "Unexpected Python SDK archive")
    wheels = sdk_root / "wheels"
    requirements = (root / "tools/python-runtime/requirements-ios-resolver.txt").read_text()
    expected = set(re.findall(r"--hash=sha256:([a-f0-9]{64})", requirements))
    wheel_files = list(wheels.iterdir())
    require(len(wheel_files) == len(expected) == 3 and all(p.suffix == ".whl" for p in wheel_files)
            and {digest(p) for p in wheel_files} == expected, "Unexpected resolver wheel inventory")
    (root / "Vendors/Python").mkdir(exist_ok=False)
    shutil.copyfile(sdk, root / "Vendors/Python" / SDK)
    dst = root / ".python-runtime/wheels"
    dst.mkdir(parents=True, exist_ok=False)
    for wheel in wheel_files:
        shutil.copyfile(wheel, dst / wheel.name)


def archive_files(archive):
    observed = set()
    files = {}
    for info in archive.infolist():
        name = info.filename
        path = PurePosixPath(name)
        canonical = unicodedata.normalize("NFC", name.rstrip("/")).casefold()
        require(canonical not in observed and not path.is_absolute() and ".." not in path.parts
                and "\\" not in name and not stat.S_ISLNK(info.external_attr >> 16), "Unsafe or duplicate IPA member")
        observed.add(canonical)
        require(name == "Payload/" or name.startswith(PREFIX), "Unexpected item outside audit app")
        if not info.is_dir():
            files[name.removeprefix(PREFIX)] = info
    return files


def inspect_python_runtime(root, app):
    path = root / "tools/python-runtime/verify_python_bundle.py"
    require(digest(path) == PYTHON_INSPECTOR_SHA, "Unreviewed Python inspector")
    text = path.read_text()
    require(text.count("com.voicematrix.app") == 2, "Verifier anchor drift")
    sys.path.insert(0, str(path.parent))
    context = {"__file__": str(path), "__name__": "audit_python_inspector"}
    # Real unmodified checks, parameterized only for main and generated framework bundle IDs.
    exec(compile(text.replace("com.voicematrix.app", AUDIT_ID), str(path), "exec"), context)
    result = context["inspect"](app)
    require(len(result["native"]) == 69 and len(result["wheels"]) == 3, "Python proof incomplete")
    return {"native": len(result["native"]), "wheels": len(result["wheels"])}


def verify_device_binary(handle):
    header = handle.read(32)
    require(len(header) == 32, "Truncated app executable")
    magic, cpu, _, filetype, commands, length, _, _ = struct.unpack("<8I", header)
    require((magic, cpu, filetype) == (0xFEEDFACF, 0x100000C, 2) and 1 <= commands <= 512
            and 8 <= length <= 1024 * 1024, "Executable is not thin ARM64")
    raw = handle.read(length)
    require(len(raw) == length, "Truncated Mach-O load-command table")
    offset, platforms = 0, []
    for _ in range(commands):
        require(offset + 8 <= length, "Malformed Mach-O command layout")
        cmd, size = struct.unpack_from("<2I", raw, offset)
        require(size >= 8 and size % 8 == 0 and offset + size <= length, "Malformed Mach-O command size")
        if cmd == 0x32:
            require(size >= 24, "Malformed Mach-O build-version command")
            platforms.append(struct.unpack_from("<I", raw, offset + 8)[0])
        offset += size
    require(offset == length and platforms == [2], "Mach-O platform is not physical iOS")


def inspect(root, app, ipa, baseline, fixture, expected_fixture, models_path):
    require(identity(baseline) == BASELINE, "Original production IPA differs or is missing")
    require(not os.path.samefile(ipa, baseline) and not ipa.is_symlink(), "Audit IPA must be separate")
    proof = inspect_python_runtime(root, app)
    main_file = app / "Info.plist"
    require(plistlib.loads(main_file.read_bytes())["CFBundleIdentifier"] == AUDIT_ID, "Inspected separate app identity drift")
    expected = staged_model_inventories(root, models_path, include_dependencies=True)
    notices = {"ParakeetNotices", "DiarizationNotices"}
    for notice in notices:
        expected[notice] = {path.name: identity(path) for path in (models_path / notice).iterdir()}
    mp4 = fixture / "strict-f5-licensed.mp4"
    fixture_json = fixture / "strict-f5-fixture.json"
    authorized_media = {"strict-f5-licensed.mp4": identity(mp4)}
    require(authorized_media["strict-f5-licensed.mp4"]["sha256"] == expected_fixture, "Fixture differs from generated manifest")
    for p in (root / "tests/fixtures/DiagnosticVoices").rglob("*.wav"):
        authorized_media["DiagnosticVoices/" + p.relative_to(root / "tests/fixtures/DiagnosticVoices").as_posix()] = identity(p)
    require(len(authorized_media) == 2, "Expected fixture and one deterministic neutral prior voice")
    with zipfile.ZipFile(ipa) as archive:
        files = archive_files(archive)
        bio = lambda name: archive.open(files[name])
        def verify(name, pinned):
            with bio(name) as handle:
                require(files[name].file_size == pinned["size"]
                        and hashlib.file_digest(handle, "sha256").hexdigest() == pinned["sha256"],
                        "IPA bytes differ: " + name)
        require(files["Info.plist"].file_size <= 65536, "Oversized app identity")
        info = plistlib.loads(archive.read(files["Info.plist"]))
        require(info.get("CFBundleIdentifier") == AUDIT_ID and info.get("CFBundleShortVersionString") == "0.4.14"
                and str(info.get("CFBundleVersion")) == "17" and not info.get("UIFileSharingEnabled")
                and info.get("UIDeviceFamily") == [1], "Audit target identity or isolation drift")
        with bio(info["CFBundleExecutable"]) as handle:
            verify_device_binary(handle)
        shader = "mlx-swift_Cmlx.bundle/default.metallib"
        with bio(shader) as handle:
            require(files[shader].file_size >= 1024 and handle.read(4) == b"MTLB", "Missing Apple MLX shader")
        for model, rows in expected.items():
            prefix = model + "/"
            require({name.removeprefix(prefix) for name in files if name.startswith(prefix)} == set(rows),
                    "Unexpected or missing IPA model/notice resources")
            for name, pinned in rows.items():
                verify(prefix + name, pinned)
        allowed_media_extensions = {".mp4", ".mov", ".mkv", ".wav", ".aiff", ".aif", ".mp3", ".m4a", ".flac", ".ogg"}
        require({name for name in files if Path(name).suffix.casefold() in allowed_media_extensions}
                == set(authorized_media), "Unexpected media in IPA")
        require(not any(PurePosixPath(name).name.casefold() in {"laptopsettings.json", "voicematrix-pairing.json",
                    "embedded.mobileprovision"} or PurePosixPath(name).suffix.casefold() in {".vmpack", ".pth"}
                    for name in files), "Credentials or unauthorized profiles in IPA")
        for name, pinned in authorized_media.items():
            verify(name, pinned)
        verify(fixture_json.name, identity(fixture_json))
        actual = {}
        for path in app.rglob("*"):
            require(not path.is_symlink(), "Signed-format app resources must not contain symlinks")
            if path.is_file():
                actual[path.relative_to(app).as_posix()] = path
        require(set(actual) == set(files), "Archived app inventory differs from inspected build")
        for name, path in actual.items():
            if name not in authorized_media and not any(name.startswith(model + "/") for model in expected) and name != fixture_json.name:
                verify(name, identity(path))
    require(identity(baseline) == BASELINE, "Original IPA changed during verification")
    return {"auditBundleID": AUDIT_ID, "exactRuntime": RUNTIME, "baselinePreserved": True,
            "auditIPA": identity(ipa), "python": proof, "physicalIPhoneVerified": False,
            "signedBundleIsolationVerified": False, "published": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("operation", choices=("preflight", "stage", "inspect"))
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--approval", type=Path, required=True)
    parser.add_argument("--approval-sha256", required=True)
    parser.add_argument("--staged", type=Path)
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--fixture", type=Path)
    args = parser.parse_args()
    require(digest(args.approval) == args.approval_sha256, "Reviewed clearance receipt bytes differ")
    receipt = json.loads(args.approval.read_bytes())
    require_receipt(receipt)
    require(identity(args.baseline) == BASELINE, "Production IPA baseline mismatch")
    pins = {"probes/mkv-f5-ios/generate.py": "82d450e87c0e49ed83629e040916faf35cacbbaf417038b0f36cabb6cbe2604e",
            "tools/create_diagnostic_collection.py": "b3ac8cc47010327b2c273d4e69e829d6fce4b060837b91908f80b110c2ba3f88"}
    require(all(digest(ROOT / path) == sha for path, sha in pins.items()), "Audit fixture generator changed")
    if args.operation == "preflight":
        print(json.dumps({key: receipt[key] for key in ("graphSHA256", "xcodegenSHA256", "xcodeVersion", "iphoneOSSDK")},
                         sort_keys=True))
    elif args.operation == "stage":
        stage(ROOT, args.staged, ROOT / ".physical-audit-assets", args.sdk)
    elif args.operation == "inspect":
        manifest = json.loads((args.fixture / "strict-f5-fixture.json").read_bytes())
        require(manifest["license"] == "CC-BY-4.0" and manifest["syntheticVideo"] is True
                and manifest["identityVerified"] is False and len(manifest["turns"]) == 2, "Unapproved test fixture")
        result = inspect(ROOT, args.app, args.ipa, args.baseline, args.fixture,
                         manifest["mp4SHA256"], ROOT / ".physical-audit-assets")
        result.update({key: receipt[key] for key in ("graphSHA256", "xcodegenSHA256", "xcodeVersion", "iphoneOSSDK")})
        result["clearanceReceiptSHA256"] = args.approval_sha256
        result["auditSourceRevision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
