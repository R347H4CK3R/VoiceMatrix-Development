from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "VoiceMatrix"

class StrictMKVLineageTests(unittest.TestCase):
    def test_clip_and_reference_persist_only_verified_derived_lineage(self):
        for name, needles in {
            "SeparationClipHandoff.swift": ["matroskaLineage", "validMatroskaLineage"],
            "ClipSpeakerReviewStore.swift": ["receipt.matroskaLineage == source.matroskaLineage"],
            "CharacterFolderStore.swift": ["var matroskaReference:", "validMatroskaReference"],
            "LocalVideoStudio.swift": ["strictSourceLineage", "matroskaReference", "existing.matroskaReference"],
        }.items():
            text = (ROOT / name).read_text()
            for needle in needles: self.assertIn(needle, text)

    def test_separated_vocals_chain_crosses_every_persisted_hop(self):
        cases = {
            "SeparationClipHandoff.swift": ["verifiedLineage", "input.receiptSHA256"],
            "VocalSeparationView.swift": ["acceptedClip = nil", "verifiedLineage(clip", "clipLineage: lineage"],
            "SeparationStore.swift": ["clipLineage?.valid(inputSHA256: inputSHA256, frames: vocals.count / 2)", "clipLineage:current.receipt.clipLineage"],
            "LocalVideoStudio.swift": ["separatedMatroska = referenceInput", "selectedReferenceStart", "separatedClip: separatedLineage?.clip"],
            "MatroskaSourceLineage.swift": ["clipReceiptSHA256", "let vocalsSHA256:", "Double(clip.frames) / 44_100"]
        }
        missing = [(name, needle) for name, needles in cases.items()
                   for needle in needles if needle not in (ROOT / name).read_text()]
        self.assertEqual(missing, [])

    def test_standalone_native_separator_build_includes_provenance_type(self):
        project = (ROOT.parent / "probes/vocal-separation-native/project.yml").read_text()
        self.assertIn("SeparationStore.swift", project)
        self.assertIn("MatroskaSourceLineage.swift", project)

    def test_first_product_commit_validates_published_tuple_after_derivation(self):
        studio = (ROOT / "LocalVideoStudio.swift").read_text()
        run = studio.index("let output = try await LocalMatroskaWorkflow.run")
        record = studio.index("current?.sourceFile = output.derived.file", run)
        self.assertIn("LocalMatroskaWorkflow.validatePublished", studio[run:record])

    def test_strict_profile_provenance_rejects_more_than_ten_seconds(self):
        lineage = (ROOT / "MatroskaSourceLineage.swift").read_text()
        profile = lineage[lineage.index("struct MatroskaReferenceLineage:"):]
        self.assertIn("(0.5...10).contains(requestedDurationSeconds)", profile)
        self.assertIn("(10_800...240_000).contains(retainedFrames)", profile)
