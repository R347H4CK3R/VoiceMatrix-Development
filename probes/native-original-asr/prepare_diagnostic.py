"""Offline prep of a disposable diagnostic workspace; no model or corpus fetches."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import wave

ROOT = Path(__file__).resolve().parents[2]
PRODUCTION = ("OnDeviceTranscription.swift", "BundledASRPolicy.swift",
              "BundledASRAssets.swift", "LocalStudioEvidence.swift")
TDT = Path("Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT")
VENDOR_SEAM = ("AsrModels.swift", "AsrManager.swift", "AsrManager+Pipeline.swift", "Parakeet231Frontend.swift")
FIXTURES = {
    "conversion-source.wav": (108032, "8741b5ebb943f4c39006b6c7a7dd5ca92f344edb402744ad7132ee1f94ff45b4"),
    "conversion-reference.wav": (123392, "0840a3b08d2d438804e760afa54bc1c9cdf1c8b33bffdc1ab458be4ab3740cd2"),
    "holdout-sources.json": (None, "00d13f6b6054551da772c5566eb7f65ade4017ac58e5132cef7931720c83f9b8"),
    "silence.wav": (32044, "643f8a8dc8bd9c19225afffad2becfec5426180b3749cb208abdf1a6c8354efc"),
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def small_file(path, cap):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > cap:
        raise ValueError(f"Not a bounded regular source input: {path.name}")
    with path.open("rb") as stream:
        data = stream.read(cap + 1)
    if len(data) > cap:
        raise ValueError("Source input changed during read")
    return data


def silence():
    raw = io.BytesIO()
    with wave.open(raw, "wb") as out:
        out.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
        out.writeframes(bytes(32000))
    return raw.getvalue()


def exclusive(path, data):
    with path.open("xb") as output:
        output.write(data)


def prepare(dest, source_commit):
    dest = Path(dest)
    if not re.fullmatch(r"[a-f0-9]{40}", source_commit):
        raise ValueError("Invalid candidate source SHA")
    if dest.exists() or dest.is_symlink():
        raise FileExistsError(dest)
    production = {name: small_file(ROOT/"VoiceMatrix"/name, 262144) for name in PRODUCTION}
    here = Path(__file__).resolve().parent
    harness = {name: small_file(here/name, 131072) for name in ("Diagnostic.swift", "Package.swift")}
    fixtures = {name: small_file(ROOT/"tests/fixtures"/name, 262144) for name in FIXTURES if name.startswith("conversion-")}
    fixtures["holdout-sources.json"] = small_file(ROOT/"probes/reference-context-human-holdouts/sources.json", 32768)
    fixtures["silence.wav"] = silence()
    for name, (size, sha) in FIXTURES.items():
        if (size is not None and len(fixtures[name]) != size) or digest(fixtures[name]) != sha:
            raise ValueError(f"Fixture identity mismatch: {name}")
    vendor = ROOT/"Vendors/FluidAudio"
    if vendor.is_symlink() or not (vendor/"Package.swift").is_file():
        raise ValueError("Expected reviewed vendored FluidAudio source tree")
    vendor_source_hashes = {name: digest(small_file(vendor/TDT/name, 262144)) for name in VENDOR_SEAM}
    dest.mkdir(mode=0o700, parents=True, exist_ok=False)
    package = dest/"probes/native-original-asr"
    source = package/"Sources/Probe"
    source.mkdir(parents=True)
    (dest/"Vendors").mkdir()
    (dest/"Vendors/FluidAudio").symlink_to(vendor, target_is_directory=True)
    (dest/"fixtures").mkdir()
    exclusive(package/"Package.swift", harness["Package.swift"])
    exclusive(source/"Diagnostic.swift", harness["Diagnostic.swift"])
    for name, data in production.items():
        exclusive(source/name, data)
    for name, data in fixtures.items():
        exclusive(dest/"fixtures"/name, data)
    proof = dict(schemaVersion=1, sourceCommit=source_commit,
                 productionSources={name: digest(data) for name, data in production.items()},
                 diagnosticSources={name: digest(data) for name,data in harness.items()},
                 vendorSeamSources=vendor_source_hashes,
                 fixtureIdentities={name: digest(data) for name,data in fixtures.items()},
                 physicalDeviceVerified=False, fullLocalPipelineVerified=False)
    exclusive(dest/"source-proof.json", (json.dumps(proof, indent=2, sort_keys=True) + "\n").encode())
    return proof


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("source_commit")
    args = parser.parse_args()
    prepare(args.output, args.source_commit)
