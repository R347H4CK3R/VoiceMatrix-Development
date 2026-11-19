"""Portable safety checks; only Apple CI can prove native behavior/parity."""
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "probes/clip-speaker-controls/instrument_stages.py"
VENDOR = ROOT / "Vendors/FluidAudio"
MANAGER = Path("Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift")


class ClipSpeakerStageInstrumentationTests(unittest.TestCase):
    def copied_file(self, directory):
        clone = Path(directory) / "FluidAudio"
        target = clone / MANAGER
        target.parent.mkdir(parents=True)
        target.write_bytes((VENDOR / MANAGER).read_bytes())
        return clone, target

    def invoke(self, directory):
        return subprocess.run([sys.executable, str(SCRIPT), str(directory)], capture_output=True, text=True)

    def test_only_diagnostic_export_changes_and_does_not_serialize_vectors(self):
        self.assertTrue(SCRIPT.is_file(), "Probe-only stage instrumentation must exist")
        original = (VENDOR / MANAGER).read_text()
        with tempfile.TemporaryDirectory() as directory:
            clone, target = self.copied_file(directory)
            target.chmod(0o640)
            untouched = clone / "Other.swift"
            untouched.write_text("kept")
            result = self.invoke(clone)
            self.assertEqual(result.returncode, 0, result.stderr)
            patched = target.read_text()
            export_anchor = "        if let exportPath = config.embeddingExportPath {"
            after_call = "        let publicChunkEmbeddings: [ChunkEmbedding]? ="
            helpers_end = "\n/// Owns the extractor"
            self.assertEqual(original.split(export_anchor)[0], patched.split(export_anchor)[0])
            self.assertEqual(original.split(after_call)[1].split("    private func exportEmbeddings(")[0],
                             patched.split(after_call)[1].split("    /// Probe-only scalar diagnostics.")[0])
            self.assertEqual(original.split(helpers_end)[1], patched.split(helpers_end)[1])
            export = patched.split("    private func exportDiagnosticStages(")[1].split(helpers_end)[0]
            for absent in ("let embedding256:", "let rho128:", "embedding256:", "rho128:",
                           "let gamma:", "let centroids:", "encode(embeddingFeatures)", "encode(embeddings)"):
                self.assertNotIn(absent, export)
            for field in ("schemaVersion", "finite256DCount", "embeddingNorms", "pairwiseUnitEuclidean",
                          "ahcTrainingIndices", "ahcInitialPartition", "vbxNumClusters", "vbxPiMasses",
                          "centroidCount", "assignments"):
                self.assertIn(field, export)
            self.assertIn("JSONEncoder().encode", export)
            self.assertIn(".withoutOverwriting", export)
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)
            self.assertEqual(untouched.read_text(), "kept")
            self.assertEqual((VENDOR / MANAGER).read_text(), original)
            self.assertEqual(set(p.name for p in target.parent.iterdir()), {target.name})
            # A second run must fail closed without any attempt to rewrite the copy.
            self.assertNotEqual(self.invoke(clone).returncode, 0)
            self.assertEqual(target.read_text(), patched)

    def test_drift_rejects_without_partial_rewrite(self):
        with tempfile.TemporaryDirectory() as directory:
            clone, target = self.copied_file(directory)
            drift = target.read_bytes() + b"// local change\n"
            target.write_bytes(drift)
            result = self.invoke(clone)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("pinned", result.stderr)
            self.assertEqual(target.read_bytes(), drift)
            self.assertEqual(set(p.name for p in target.parent.iterdir()), {target.name})

    def test_original_tree_and_linked_manager_are_refused(self):
        original = (VENDOR / MANAGER).read_bytes()
        direct = self.invoke(VENDOR)
        self.assertNotEqual(direct.returncode, 0)
        self.assertIn("checkout", direct.stderr)
        with tempfile.TemporaryDirectory() as directory:
            clone, target = self.copied_file(directory)
            target.unlink()
            target.symlink_to(VENDOR / MANAGER)
            result = self.invoke(clone)
            self.assertNotEqual(result.returncode, 0)
            self.assertTrue(target.is_symlink())
            self.assertEqual((VENDOR / MANAGER).read_bytes(), original)
