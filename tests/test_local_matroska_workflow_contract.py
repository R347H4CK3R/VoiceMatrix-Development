from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class WorkflowContractTests(unittest.TestCase):
    def test_fixed_stages_have_native_verified_inputs(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaWorkflow.swift").read_text()
        for required in ("decideMKVStageJSON", "LocalMKVExport.export", "LocalMatroskaDerivedMedia.derive",
                         "LocalMediaAcquisition.verify", "strict-matroska-v1.json",
                         "Task.checkCancellation()", "mkvVerified", "derivedVerified"):
            self.assertIn(required, source)
        self.assertNotIn("retainMatroska", source)

    def test_admission_and_commits_require_strict_provenance(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaWorkflow.swift").read_text()
        for required in ("stageOriginal", "strictJSONObject", "validateJournalKeys",
                         "r.audioPackets * 1024 - r.discardFrames", "volumeCapacity", "800_000_000"):
            self.assertIn(required, source)
