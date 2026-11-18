"""Portable surface checks; behavioral storage and race checks live in the native app tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "VoiceMatrix"


def source(name):
    path = ROOT / (name + ".swift")
    return path.read_text() if path.exists() else ""


class ClipSpeakerReviewSurfaceTests(unittest.TestCase):
    def test_store_reuses_current_policy_and_binds_raw_overlap_to_clip(self):
        store = source("ClipSpeakerReviewStore")
        self.assertIn("LocalSpeakerDiarization.validatedForCurrentPolicy", store)
        self.assertRegex(store, r"rawOverlap\?\.sourceSHA256\s*==\s*clip\.sha256")
        for field in ("receiptSHA256", "analysisSHA256", "maximumBytes", "RetainedMediaReader.read"):
            self.assertIn(field, store)

    def test_review_uses_separate_explicit_action_without_generation_or_fallback(self):
        view = source("ClipSpeakerReviewView")
        self.assertIn("clip-speaker-review-authorization", view)
        self.assertIn("clip-speaker-review-run", view)
        self.assertIn("retained-clip-prepare-review", source("LocalVideoStudioView"))
        coordinator = source("ClipSpeakerReviewCoordinator")
        self.assertIn("LocalSpeakerDiarization.analyze", coordinator)
        self.assertIn("audio.claimProcessing()", coordinator)
        self.assertIn("audio.releaseProcessing(lease)", coordinator)
        for forbidden in ("LocalVideoStudio.run", "F5ReferenceEngine", "CharacterLibrary", "URLSession"):
            self.assertNotIn(forbidden, coordinator + view)

    def test_navigation_only_loads_review_and_invalidates_outstanding_work(self):
        view = source("ClipSpeakerReviewView")
        self.assertIn(".onDisappear", view)
        self.assertIn(".onChange(of: scene)", view)
        self.assertIn(".onChange(of: clip)", view)
        self.assertIn(".onChange(of: local.retainedSeparationSource)", view)
        self.assertEqual(view.count("review.start("), 1)
        self.assertIn("review.cancel()", view)

    def test_canonical_pcm_reader_drains_only_the_retained_clip_route(self):
        decoder = source("LocalSpeakerDiarization")
        coordinator = source("ClipSpeakerReviewCoordinator")
        self.assertIn("retainedClipFrames: clip.frames", coordinator)
        self.assertIn("func decodeRetainedClip(", decoder)
        canonical = decoder.split("func decodeRetainedClip(", 1)[1].split("private static func decode(", 1)[0]
        for required in (".primeMethod = .normal", ".endOfStream", "samples.count == expected", "SHA256.hash(data:"):
            self.assertIn(required, canonical)
        self.assertIn("if let retainedClipFrames", decoder)
        self.assertIn("try await decode(source,progress:progress)", decoder)
