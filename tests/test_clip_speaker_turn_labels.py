from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "VoiceMatrix"


class TurnLabelSurfaceTests(unittest.TestCase):
    def test_turn_controls_use_exact_model_turn_not_group_alias(self):
        view = (ROOT / "ClipSpeakerReviewView.swift").read_text()
        self.assertIn('ForEach(group.turns)', view)
        self.assertIn('review.saveTurnLabel(draft, turn: turn, for: clip)', view)
        self.assertIn('may group different speakers together', view)

    def test_no_usable_turn_is_explicit_without_silence_claim(self):
        coordinator = (ROOT / "ClipSpeakerReviewCoordinator.swift").read_text()
        self.assertIn('case .noSpeechDetected', coordinator)
        self.assertIn('Speech or overlap may still be present.', coordinator)
