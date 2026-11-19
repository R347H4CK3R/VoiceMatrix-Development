"""Narrow extraction from the one byte-verified already-public original IPA."""
import hashlib
import importlib.util
from pathlib import Path, PurePosixPath
import stat
import sys
import unicodedata
import zipfile

GATE = Path(__file__).resolve().parents[1] / "packaging_gate.py"
SPEC = importlib.util.spec_from_file_location("audit_gate", GATE)
gate = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gate)


def members(archive):
    names = set()
    rows = {}
    for entry in archive.infolist():
        name = entry.filename
        key = unicodedata.normalize("NFC", name.rstrip("/")).casefold()
        path = PurePosixPath(name)
        if key in names or path.is_absolute() or ".." in path.parts or "\\" in name or stat.S_ISLNK(entry.external_attr >> 16):
            raise ValueError("Unsafe historical IPA member")
        names.add(key)
        if not entry.is_dir():
            rows[name] = entry
    return rows


def extract_pins(archive, rows, parent, locks):
    if set(locks) != {"F5TTS", "Diarization"}:
        raise ValueError("Historical IPA may contribute only these exact two model groups")
    prefix = "Payload/VoiceMatrix.app/"
    selected = {}
    for group, files in locks.items():
        for name, expected in files.items():
            row = rows[prefix + group + "/" + name]
            if row.file_size != expected["size"]:
                raise ValueError("Historical model variant differs")
            selected[(group, name)] = (row, expected)
    parent.mkdir(exist_ok=False)
    for (group, name), (row, expected) in selected.items():
        target = parent / group / name
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(row) as src, target.open("xb") as out:
            digest = hashlib.sha256()
            size = 0
            while data := src.read(1048576):
                size += len(data)
                if size > expected["size"]:
                    raise ValueError("Historical entry exceeds pinned size")
                digest.update(data)
                out.write(data)
        if size != expected["size"] or digest.hexdigest() != expected["sha256"]:
            raise ValueError("Historical entry hash differs; no alternate fetch permitted")
    for group, files in locks.items():
        gate.exact_tree(parent / group, files)


def main(original, out):
    if gate.identity(original) != gate.BASELINE:
        raise ValueError("Wrong existing public release")
    root = gate.ROOT
    lock = gate.models(root)
    allowed = {k: lock[k] for k in ("F5TTS", "Diarization")}
    for name in gate.F5_NOTICES:
        allowed["F5TTS"]["Notices/" + name] = gate.identity(root / "tools/listening_licenses" / name)
    allowed["Diarization"]["resource-lock.json"] = gate.identity(root / gate.LOCKS["Diarization"][0])
    # Generate the reviewed proof of the checked historical bytes, do not inherit old release metadata.
    with zipfile.ZipFile(original) as archive:
        extract_pins(archive, members(archive), out, allowed)
    import json
    allowed_f5 = lock["F5TTS"]
    manifest = {"schemaVersion": 1, "engine": "F5TTS_v1_Base",
        "runtimeRevision": "a57702e6f523fa36ac5532d2bdc5f35f701a052c",
        "modelRepository": "aufklarer/F5TTS-v1-Base-MLX-fp16",
        "modelRevision": "685e88161a2841a5f102a6f8094613ba7131e350",
        "files": [dict(path=n, **p) for n, p in sorted(allowed_f5.items()) if not n.startswith("Notices/")]}
    (out / "F5TTS/voicematrix-engine.json").write_text(json.dumps(manifest, sort_keys=True), encoding="utf-8")


if __name__ == "__main__":
    main(*map(Path, sys.argv[1:]))
