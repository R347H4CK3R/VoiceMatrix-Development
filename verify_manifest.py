"""Verify reviewed, SHA-bound native run inputs; stdlib only."""
import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat

MANIFEST = "run-inputs.json"
MAX_FILE_BYTES = 2 * 1024 * 1024
MAX_FILES = 32
REQUIRED = frozenset({'test_compare_cli.py', 'SwiftFrontend/Sources/Parakeet231/Parakeet231Frontend.swift', 'SwiftFrontend/Sources/Parakeet231CLI/main.swift', 'Oracle/original-buffers/ATTRIBUTION.md', 'Oracle/original-buffers/provenance.json', 'SwiftFrontend/Package.swift', 'verify_manifest.py', 'original-failed-baseline.json', 'neutral-speech.txt', 'SwiftFrontend/Tests/Parakeet231Tests/Parakeet231Tests.swift', 'requirements.txt', 'stage-diagnostic-baseline.json', 'THIRD-PARTY-NOTICES.txt', 'Oracle/original-buffers/window.f32le', 'SwiftFrontend/README.md', 'compare_cli.py', 'Oracle/original-buffers/filterbank.f32le', 'Oracle/oracle.py', 'Oracle/LICENSE-NeMo', 'README.md', 'SwiftFrontend/LICENSE', 'Oracle/test_generate.py', 'Oracle/generate.py'})

def strict_object(items):
    result = dict(items)
    if len(result) != len(items):
        raise ValueError("Duplicate JSON key")
    return result

def clean_path(root, raw):
    if not isinstance(raw, str) or not re.fullmatch(r"[A-Za-z0-9._/-]+", raw):
        raise ValueError("Invalid file path")
    path = PurePosixPath(raw)
    if path.is_absolute() or not path.parts or '..' in path.parts or str(path) != raw:
        raise ValueError("Unsafe file path")
    result = root
    for component in path.parts:
        result = result / component
        try:
            if stat.S_ISLNK(result.lstat().st_mode):
                raise ValueError("Symlink input")
        except OSError as err:
            raise ValueError("Input does not exist") from err
    return result

def bounded_read(path, limit):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
        raise ValueError("Input is not a bounded regular file")
    with path.open("rb") as f:
        data = f.read(limit + 1)
    if len(data) > limit:
        raise ValueError("File grew past limit")
    return data

def verify(root, expected, required=(), *, stage=None):
    root = Path(root).resolve(strict=True)
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise ValueError("Invalid manifest SHA-256")
    raw = bounded_read(clean_path(root, MANIFEST), 32 * 1024)
    if hashlib.sha256(raw).hexdigest() != expected:
        raise ValueError("Run manifest SHA-256 mismatch")
    value = json.loads(raw, object_pairs_hook=strict_object)
    if not isinstance(value, dict) or set(value) != {"schema", "files"} or type(value["schema"]) is not int or value["schema"] != 1:
        raise ValueError("Unsupported manifest schema")
    files = value["files"]
    if not isinstance(files, list) or not 1 <= len(files) <= MAX_FILES:
        raise ValueError("Invalid manifest file count")
    seen = set()
    verified = {}
    for row in files:
        if not isinstance(row, dict) or set(row) != {"path", "sha256", "size"}:
            raise ValueError("Invalid manifest entry")
        name = row["path"]
        path = clean_path(root, name)
        if name in seen or name == MANIFEST:
            raise ValueError("Duplicate or recursive manifest file")
        seen.add(name)
        size, digest = row["size"], row["sha256"]
        if type(size) is not int or not 0 <= size <= MAX_FILE_BYTES or not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise ValueError("Invalid entry size or digest")
        contents = bounded_read(path, size)
        if len(contents) != size or hashlib.sha256(contents).hexdigest() != digest:
            raise ValueError("Input size or SHA-256 mismatch: " + name)
        verified[name] = contents
    if not set(required) <= seen:
        raise ValueError("Required files missing from run manifest")
    if stage is not None:
        stage = Path(stage)
        stage.mkdir(mode=0o700, exist_ok=False)
        for name, contents in {MANIFEST: raw, **verified}.items():
            target = stage / name
            target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            with target.open("xb") as stream:
                stream.write(contents)
    return len(seen)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--stage", type=Path)
    args = parser.parse_args()
    print("Verified", verify(args.root, args.manifest_sha256, REQUIRED, stage=args.stage), "reviewed run inputs.")
