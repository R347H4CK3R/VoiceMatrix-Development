"""Source wiring checks; native navigation coverage is authored but requires Xcode."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class StandaloneVoiceEntryTests(unittest.TestCase):
 def test_voices_has_direct_local_studio_path(self):
  source=(ROOT/'VoiceMatrix/CharacterLibraryView.swift').read_text().split('struct CharacterPickerView:')[0]
  self.assertIn('NavigationLink { LocalVideoStudioView() }',source)
  self.assertIn('accessibilityIdentifier("create-local-voice")',source)
  self.assertNotIn('Browse the laptop catalog to get started',source)
 def test_initial_state_does_not_require_laptop(self):
  source=(ROOT/'VoiceMatrix/CharacterLibrary.swift').read_text()
  self.assertNotIn('var message = "Browse your laptop catalog',source)
  self.assertIn('Laptop sync is optional.',source)
  tutorial=(ROOT/'VoiceMatrix/App.swift').read_text()
  self.assertNotIn("1. Choose your Voices folder",tutorial)
  self.assertIn("Create or import voices on this iPhone",tutorial)
