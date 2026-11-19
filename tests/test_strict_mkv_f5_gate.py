"""Preflight strictly limits the real-F5 simulator gate; native inference is CI-only."""
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class StrictMKVF5GateTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg required for media preflight")
    def test_build_uses_two_pinned_nonoverlapping_recordings(self):
        with tempfile.TemporaryDirectory() as temporary:
            out = pathlib.Path(temporary) / "fixture"
            subprocess.run([sys.executable, "probes/mkv-f5-ios/generate.py", str(out)],
                           cwd=ROOT, check=True, capture_output=True, timeout=60)
            manifest = json.loads((out / "strict-f5-fixture.json").read_text())
            self.assertEqual(len(manifest["turns"]), 2)
            self.assertNotEqual(manifest["turns"][0]["sha256"], manifest["turns"][1]["sha256"])
            self.assertLess(manifest["turns"][0]["end"], manifest["turns"][1]["start"])
            self.assertFalse(manifest["identityVerified"])
            self.assertTrue((out / "strict-f5-licensed.mp4").is_file())

    def test_native_gate_requires_real_synthesis_and_metadata_only_artifact(self):
        gate = (ROOT / ".github/workflows/strict-mkv-f5-ios.yml")
        self.assertTrue(gate.is_file())
        source = gate.read_text()
        for token in ("contents: read", "persist-credentials: false", "verification/strict-mkv-f5-ios",
                      "testRealStrictSourceSavesTwoReferences",
                      "tools/bundle_asr.py", "tools/bundle_diarization.py", "tools/character_package.py",
                      "-only-testing:VoiceMatrixTests/StrictMatroskaF5Tests"):
            self.assertIn(token, source)
        artifact = source.split("uses: actions/upload-artifact@", 1)[1]
        self.assertIn("strict-f5-report.json", artifact)
        for secret in (".wav", ".mp4", ".mkv", ".xcresult", "strict-f5-native.log"):
            self.assertNotIn(secret, artifact)

    def test_metadata_oracle_refuses_same_process_or_same_reference(self):
        digest = lambda number: f"{number:064x}"
        row = lambda index: dict(voiceID=f"voice-{index}", referenceSHA256=digest(index),
                                 manifestSHA256=digest(index+1), clipSHA256=digest(index+2),
                                 previewSHA256=digest(index+3), speechSHA256=digest(index+4),
                                 wordErrorRate=0.0)
        evidence = dict(metadataOnly=True, priorVoicePreserved=True, identityVerified=False,
                        physicalDeviceVerified=False, liveURLVerified=False, phaseOnePID=10,
                        phaseTwoPID=11, distinctFixtureTurns=2, originalSHA256=digest(1),
                        mkvSHA256=digest(2), derivedSHA256=digest(3), generated=[row(10), row(30)])
        with tempfile.TemporaryDirectory() as temporary:
            path = pathlib.Path(temporary) / "report.json"
            def verify(data):
                path.write_text(json.dumps(data))
                return subprocess.run([sys.executable, "probes/mkv-f5-ios/verify.py", str(path)],
                                      cwd=ROOT, capture_output=True, timeout=10).returncode
            self.assertEqual(verify(evidence), 0)
            self.assertNotEqual(verify(dict(evidence, phaseTwoPID=10)), 0)
            evidence["generated"][1]["referenceSHA256"] = evidence["generated"][0]["referenceSHA256"]
            self.assertNotEqual(verify(evidence), 0)

    def test_model_staging_preserves_tracked_placeholder_and_refuses_unknown_files(self):
        import textwrap
        gate = (ROOT / ".github/workflows/strict-mkv-f5-ios.yml").read_text()
        script = textwrap.dedent(gate.split("<<'PY_ASSETS'\n", 1)[1].split("\n          PY_ASSETS", 1)[0])
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            target = root / "VoiceMatrix/Resources/F5TTS"
            target.mkdir(parents=True)
            marker = target / "BUILD-INPUTS.txt"
            marker.write_bytes((ROOT / "VoiceMatrix/Resources/F5TTS/BUILD-INPUTS.txt").read_bytes())
            source = root / "character-resources/F5TTS"
            source.mkdir(parents=True)
            (source / "config.json").write_text("{}")
            def run():
                return subprocess.run([sys.executable, "-c", script], cwd=root, capture_output=True, timeout=15)
            unknown = target / "unexpected.bin"
            unknown.write_bytes(b"preserve")
            self.assertNotEqual(run().returncode, 0)
            self.assertEqual(unknown.read_bytes(), b"preserve")
            self.assertFalse((target / "config.json").exists())
            unknown.unlink()
            result = run()
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(marker.read_bytes(), (ROOT / "VoiceMatrix/Resources/F5TTS/BUILD-INPUTS.txt").read_bytes())
            self.assertEqual((target / "config.json").read_text(), "{}")
