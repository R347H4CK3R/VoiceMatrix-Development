import io
import json
import struct
import tempfile
from contextlib import redirect_stdout
import unittest
import uuid
import wave
from pathlib import Path
from unittest.mock import patch

import yaml

from tools.test_shell import check_bash_syntax

ROOT = Path(__file__).resolve().parents[1]


class ClipSpeakerReviewUIFixtureTests(unittest.TestCase):
    def test_speaker_section_identifier_is_header_only_and_failures_keep_hierarchy(self):
        view = (ROOT / "VoiceMatrix/ClipSpeakerReviewView.swift").read_text()
        self.assertIn('} header: {\n                        Text("Speaker guess \\(group.id)")', view)
        self.assertIn('.accessibilityIdentifier("clip-speaker-review-label-" + group.id)', view)
        ui = (ROOT / "VoiceMatrixUITests/ClipSpeakerReviewUITests.swift").read_text()
        self.assertIn('XCTAttachment(string: app.debugDescription)', ui)

    def test_oracle_rejects_missing_changed_and_unexpected_app_outputs(self):
        from tools.seed_clip_speaker_review_ui import seed, check, sha, SOURCE_JOB_ID
        with tempfile.TemporaryDirectory() as location:
            base = Path(location)
            container = base / "container"
            container.mkdir()
            original = base / "wave.wav"
            with wave.open(str(original), "wb") as w:
                w.setparams((1, 2, 16_000, 0, "NONE", "not compressed"))
                w.writeframes(struct.pack("<h", 4000) * 128_000)
            identity = {"simulatorID": str(uuid.uuid4()), "bundleID": "com.voicematrix.app"}
            receipt_path = base / "baseline.json"
            seed(container, original, receipt_path, identity)
            with self.assertRaises(FileExistsError):
                seed(container, original, receipt_path, identity)
            with self.assertRaises(AssertionError):
                check(container, receipt_path, identity)

            support = container / "Library/Application Support"
            clips = support / "VocalSeparation"
            reviews = support / "VocalSeparation-SpeakerReviews"
            reviews.mkdir()
            for seconds in (5, 8):
                identifier = str(uuid.uuid4()).upper()
                folder = clips / ("Clip-" + identifier)
                folder.mkdir(parents=True)
                frames = seconds * 44_100
                pcm = struct.pack("<ff", 0.125, 0.125) * frames
                data = (b"RIFF" + struct.pack("<I", 36 + len(pcm)) + b"WAVEfmt "
                        + struct.pack("<IHHIIHH", 16, 3, 2, 44_100, 352_800, 8, 32)
                        + b"data" + struct.pack("<I", len(pcm)) + pcm)
                (folder / "clip.wav").write_bytes(data)
                clip_receipt = dict(id=identifier, sourceJobID=SOURCE_JOB_ID, sourceSHA256=sha(original.read_bytes()),
                                    requestedStart=0, requestedSeconds=seconds, actualStart=0, frames=frames,
                                    clipSHA256=sha(data))
                metadata = json.dumps(clip_receipt).encode()
                (folder / "receipt.json").write_bytes(metadata)
                if seconds != 8:
                    continue
                file = reviews / (identifier + ".json")
                binding = dict(clipID=identifier, clipSHA256=sha(data), receiptSHA256=sha(metadata), analysisSHA256="a" * 64)
                revision = "df2625ac79a7ac6b65ad868fee6d80f320da4232"
                record = dict(version=1, binding=binding, analysis=dict(seconds=8, modelRevision=revision, selectionPolicyVersion=5,
                    rawOverlap=dict(sourceSHA256=sha(data), version=1, modelRevision=revision, duration=8, counts=[1]),
                    segments=[dict(speaker="anonymous", start=1, end=7)]),
                    aliases=[dict(binding=binding, speaker="anonymous", name="QA narrator")])
                file.write_text(json.dumps(record))
            captured = io.StringIO()
            with redirect_stdout(captured):
                check(container, receipt_path, identity)
            self.assertIs(json.loads(captured.getvalue())["speakerIdentityVerified"], False)
            with self.assertRaises(AssertionError):
                check(container, receipt_path, {**identity, "bundleID": "other.app"})
            record["aliases"][0]["binding"] = {**binding, "receiptSHA256": "0" * 64}
            file.write_text(json.dumps(record))
            with self.assertRaises(AssertionError):
                check(container, receipt_path, identity)
            record["aliases"][0]["binding"] = binding
            file.write_text(json.dumps(record))
            voice_root = support / "CharacterReferences"
            voice_root.mkdir()
            profile = voice_root / "unrequested-profile.json"
            profile.write_text("{}")
            with self.assertRaises(AssertionError):
                check(container, receipt_path, identity)
            profile.unlink()
            (container / "Documents").mkdir(exist_ok=True)
            unexpected = container / "Documents/unrequested-preview.wav"
            unexpected.write_bytes(b"bad")
            with self.assertRaises(AssertionError):
                check(container, receipt_path, identity)
            unexpected.unlink()
            source = support / "LocalVideoStudio" / SOURCE_JOB_ID.lower() / "source.wav"
            source.write_bytes(b"changed")
            with self.assertRaises(AssertionError):
                check(container, receipt_path, identity)
            self.assertEqual(source.read_bytes(), b"changed")

    def test_seed_rejects_short_input_without_creating_retained_job(self):
        from tools.seed_clip_speaker_review_ui import seed
        with tempfile.TemporaryDirectory() as location:
            base = Path(location)
            container = base / "container"
            container.mkdir()
            invalid = base / "invalid.wav"
            with wave.open(str(invalid), "wb") as w:
                w.setparams((1, 2, 16_000, 0, "NONE", "not compressed"))
                w.writeframes(struct.pack("<h", 4000) * 32_000)
            with self.assertRaises(AssertionError):
                seed(container, invalid, base / "receipt.json", {})
            self.assertFalse((container / "Library").exists())

    def test_simulator_authority_rejects_unrelated_container(self):
        from tools.seed_clip_speaker_review_ui import verify_container, BUNDLE_ID
        with tempfile.TemporaryDirectory() as location:
            simulator = str(uuid.uuid4()).upper()
            base = Path(location).resolve() / "CoreSimulator/Devices" / simulator / "data/Containers/Data/Application"
            owned = base / str(uuid.uuid4()).upper()
            unrelated = base / str(uuid.uuid4()).upper()
            for path in (owned, unrelated):
                path.mkdir(parents=True)
            with patch("tools.seed_clip_speaker_review_ui.subprocess.check_output", return_value=f"{owned}\n") as query:
                canonical, identity = verify_container(owned, simulator)
                self.assertEqual(canonical, owned)
                self.assertEqual(identity["bundleID"], BUNDLE_ID)
                query.assert_called_once_with(["xcrun", "simctl", "get_app_container", simulator, BUNDLE_ID, "data"], text=True)
                with self.assertRaises(AssertionError):
                    verify_container(unrelated, simulator)

    def test_workflow_runs_exact_ui_test_with_pinned_real_speech_fixture(self):
        workflow = ROOT / ".github/workflows/retained-clip-speaker-review-ui.yml"
        self.assertTrue(workflow.is_file(), "Separate owned-simulator UI gate required")
        job = yaml.safe_load(workflow.read_text())
        self.assertEqual(job["permissions"], {"contents": "read"})
        commands = [step["run"] for step in job["jobs"]["ui"]["steps"] if "run" in step]
        for body in commands:
            check_bash_syntax(body)
        command = "\n".join(commands)
        for required in ("probes/clip-speaker-review/prepare.py", "single.wav", "tools.seed_clip_speaker_review_ui seed",
                         "tools.seed_clip_speaker_review_ui check", "testReviewRequiresFreshConsentAndKeepsClipSpecificAliasAcrossRelaunch",
                         "xcodebuild test-without-building", "get_app_container", "TEST EXECUTE SUCCEEDED"):
            self.assertIn(required, command)
        self.assertNotIn("publish", command)
