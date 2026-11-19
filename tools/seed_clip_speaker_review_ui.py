"""Seed real fixture bytes in an owned CI simulator, then audit the actual UI effects."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import struct
import subprocess
import uuid
import wave

BUNDLE_ID = "com.voicematrix.app"
SOURCE_JOB_ID = "E8111111-1111-4111-8111-111111111111"
VOICE_ROOTS = ("CharacterReferences", "CharacterReviews", "CharacterNames", "CatalogSpeechChecks")
MEDIA = {".wav", ".caf", ".m4a", ".mp3", ".aif", ".aiff", ".flac", ".mov", ".mp4", ".mkv"}
MODEL_REVISION = "df2625ac79a7ac6b65ad868fee6d80f320da4232"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def inventory(root, suffixes=None):
    assert not root.is_symlink(), "Do not follow fixture links"
    out = {}
    for path in sorted(root.rglob("*")):
        assert not path.is_symlink(), "Do not follow fixture links"
        if path.is_file() and (suffixes is None or path.suffix.lower() in suffixes):
            out[path.relative_to(root).as_posix()] = sha(path.read_bytes())
    return out


def media_inventory(container):
    return {directory + "/" + filename: digest
            for directory in ("Library/Application Support", "Documents", "tmp")
            for filename, digest in inventory(container / directory, MEDIA).items()}


def verify_container(container, simulator):
    canonical = container.resolve(strict=True)
    assert str(uuid.UUID(simulator)).upper() == simulator.upper()
    reported = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", simulator, BUNDLE_ID, "data"], text=True).strip())
    assert reported.is_absolute() and reported.resolve(strict=True) == canonical, "Not the selected app container"
    assert canonical.parts[-6:-1] == (simulator, "data", "Containers", "Data", "Application")
    assert canonical.parents[5].name == "Devices" and canonical.parents[6].name == "CoreSimulator"
    uuid.UUID(canonical.name)
    identity = {"simulatorRoot": str(canonical.parents[4]), "simulatorID": simulator, "bundleID": BUNDLE_ID}
    return canonical, identity


def seed(container, fixture, baseline, identity, expected_sha=None):
    if baseline.exists():
        raise FileExistsError("Refuse to overwrite fixture baseline")
    support = container / "Library/Application Support"
    jobs = support / "LocalVideoStudio"
    for path in (jobs, support / "VocalSeparation", support / "VocalSeparation-SpeakerReviews"):
        assert not path.exists() and not path.is_symlink(), "Use a fresh owned simulator"
    assert not fixture.is_symlink() and 44 < fixture.stat().st_size <= 260_000
    data = fixture.read_bytes()
    if expected_sha is not None:
        assert sha(data) == expected_sha, "Fixture hash differs from the licensed fixture manifest"
    with wave.open(io.BytesIO(data), "rb") as source:
        channels, width, sample_rate, frames, compression, _ = source.getparams()
        assert (channels, width, sample_rate, frames, compression) == (1, 2, 16_000, 128_000, "NONE")
        assert len(source.readframes(frames)) == frames * width
    job = jobs / SOURCE_JOB_ID.lower()
    job.mkdir(parents=True)
    with (job / "source.wav").open("xb") as output:
        output.write(data)
    with (job / "job.json").open("x") as output:
        json.dump(dict(id=SOURCE_JOB_ID, created=900000010, updated=900000010,
                       stage="Retained licensed speech UI fixture", message="No analysis has started.",
                       sourceFile="source.wav", sourceSHA256=sha(data), completed=True, events=[]),
                  output, sort_keys=True)
    with baseline.open("x") as output:
        json.dump(dict(identity=identity, beforeContainer=str(container), sourceSHA256=sha(data),
                       jobs=inventory(jobs), voices={name: inventory(support / name) for name in VOICE_ROOTS},
                       media=media_inventory(container)), output, sort_keys=True)


def check(container, baseline, identity):
    before = json.loads(baseline.read_text())
    assert before["identity"] == identity, "Owned simulator/app identity changed"
    support = container / "Library/Application Support"
    assert inventory(support / "LocalVideoStudio") == before["jobs"], "Retained sources or job files changed"
    assert {name: inventory(support / name) for name in VOICE_ROOTS} == before["voices"], "Voice or reference data changed"

    clips_root = support / "VocalSeparation"
    assert clips_root.is_dir() and not clips_root.is_symlink(), "No owned clips persisted"
    folders = list(clips_root.iterdir())
    assert len(folders) == 2, "Expected two explicitly prepared clips and no stems or processing artifacts"
    clips = {}
    approved_media = dict(before["media"])
    for folder in folders:
        assert folder.is_dir() and not folder.is_symlink() and folder.name.startswith("Clip-")
        assert set(path.name for path in folder.iterdir()) == {"clip.wav", "receipt.json"}
        media, receipt_file = folder / "clip.wav", folder / "receipt.json"
        assert not media.is_symlink() and not receipt_file.is_symlink()
        data, receipt_bytes = media.read_bytes(), receipt_file.read_bytes()
        receipt = json.loads(receipt_bytes)
        identifier, frames = receipt["id"], receipt["frames"]
        assert str(uuid.UUID(identifier)).upper() == identifier and folder.name == "Clip-" + identifier
        assert receipt["sourceJobID"] == SOURCE_JOB_ID and receipt["sourceSHA256"] == before["sourceSHA256"]
        assert receipt["requestedStart"] == receipt["actualStart"] == 0
        seconds = receipt["requestedSeconds"]
        assert seconds in (5, 8) and seconds not in clips
        assert frames in (seconds * 44_100, seconds * 44_100 - 1)
        assert len(data) == 44 + frames * 8 and sha(data) == receipt["clipSHA256"]
        assert data[:4] == b"RIFF" and data[8:16] == b"WAVEfmt " and data[36:40] == b"data"
        assert struct.unpack_from("<HHI", data, 20) == (3, 2, 44_100)
        clips[seconds] = (identifier, receipt["clipSHA256"], sha(receipt_bytes), frames)
        approved_media[media.relative_to(container).as_posix()] = receipt["clipSHA256"]
    assert set(clips) == {5, 8}
    assert media_inventory(container) == approved_media, "Unexpected media or mutation"
    reviews = support / "VocalSeparation-SpeakerReviews"
    assert reviews.is_dir() and not reviews.is_symlink(), "No owned review persisted"
    expected_sidecars = {reviews / (clip[0] + ".json") for clip in clips.values()}
    assert set(reviews.iterdir()) == expected_sidecars, "Exactly two explicitly authorized reviews must persist"
    for seconds, (clip_id, clip_sha, receipt_sha, frames) in clips.items():
        sidecar = reviews / (clip_id + ".json")
        assert sidecar.is_file() and not sidecar.is_symlink()
        record = json.loads(sidecar.read_text())
        binding = record["binding"]
        assert record["version"] == 1 and binding["clipID"] == clip_id and binding["clipSHA256"] == clip_sha
        assert binding["receiptSHA256"] == receipt_sha and re.fullmatch(r"[0-9a-f]{64}", binding["analysisSHA256"])
        analysis = record["analysis"]
        assert analysis["selectionPolicyVersion"] == 5 and analysis["modelRevision"] == MODEL_REVISION
        assert abs(analysis["seconds"] - frames / 44_100) <= 1 / 16000 + 1e-9
        overlap = analysis["rawOverlap"]
        assert overlap["sourceSHA256"] == clip_sha and overlap["modelRevision"] == MODEL_REVISION
        assert overlap["version"] == 1 and overlap["duration"] == analysis["seconds"] and any(n > 0 for n in overlap["counts"])
        assert analysis["segments"], "Expected actual model turns for each clip"
        if seconds == 8:
            first = min(analysis["segments"], key=lambda turn: (turn["start"], turn["speaker"]))
            assert record["aliases"] == [{"binding": binding, "name": "QA narrator", "speaker": first["speaker"]}]
            assert record.get("turnLabels") == [{"binding": binding, "name": "QA relabeled turn",
                                                  "turn": {"index": 0, **analysis["segments"][0]}}]
            reviewed_clip_seconds = analysis["seconds"]
        else:
            assert record["aliases"] == [] and not record.get("turnLabels"), "Labels propagated across clips"
    proof = {"identity": identity, "beforeContainer": before["beforeContainer"], "afterContainer": str(container),
             "sourceSHA256": before["sourceSHA256"], "reviewedClipSeconds": reviewed_clip_seconds,
             "twoExplicitlyAnalyzedClips": True, "clipSpecificAlias": True, "exactTurnLabel": True,
             "preservedSourcesAndVoices": True, "noUnexpectedMedia": True, "speakerIdentityVerified": False}
    print(json.dumps(proof, sort_keys=True))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["seed", "check"])
    parser.add_argument("container", type=Path)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("--simulator-id", required=True)
    parser.add_argument("--fixture", type=Path)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    container, identity = verify_container(args.container, args.simulator_id)
    if args.mode == "seed":
        if not args.fixture or not args.manifest:
            parser.error("seed requires --fixture and --manifest from the licensed fixture builder")
        manifest = json.loads(args.manifest.read_text())
        assert manifest["sampleRate"] == 16_000
        single, = [case for case in manifest["cases"] if case["name"] == "single"]
        assert args.fixture.name == "single.wav" and single["frames"] == 128_000
        seed(container, args.fixture, args.baseline, identity, expected_sha=single["audioSHA256"])
    else:
        check(container, args.baseline, identity)


if __name__ == "__main__":
    main()
