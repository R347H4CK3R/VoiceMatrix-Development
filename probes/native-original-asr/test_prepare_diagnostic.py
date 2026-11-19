from pathlib import Path
import json
import tempfile
import unittest
from prepare_diagnostic import prepare, ROOT, PRODUCTION

class PreparationTests(unittest.TestCase):
    def test_stages_exact_production_and_original_fixtures(self):
        with tempfile.TemporaryDirectory() as scratch:
            dest = Path(scratch) / "stage"
            proof = prepare(dest, "a" * 40)
            for name in PRODUCTION:
                self.assertEqual((dest/"probes/native-original-asr/Sources/Probe"/name).read_bytes(),
                                 (ROOT/"VoiceMatrix"/name).read_bytes())
            self.assertEqual(proof["sourceCommit"], "a" * 40)
            self.assertEqual(len(proof["productionSources"]), 4)
            self.assertEqual((dest/"Vendors/FluidAudio").resolve(), ROOT/"Vendors/FluidAudio")
            self.assertTrue((dest/"fixtures/silence.wav").is_file())
            self.assertFalse((dest/"models").exists())

    def test_no_clobber_or_malformed_identity(self):
        with tempfile.TemporaryDirectory() as scratch:
            dest = Path(scratch) / "stage"
            with self.assertRaises(ValueError): prepare(dest, "not-a-sha")
            self.assertFalse(dest.exists())
            dest.mkdir(); (dest/"keep").write_text("unchanged")
            with self.assertRaises(FileExistsError): prepare(dest, "b" * 40)
            self.assertEqual((dest/"keep").read_text(), "unchanged")
