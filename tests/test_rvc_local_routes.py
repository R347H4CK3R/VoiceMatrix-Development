"""Source wiring checks only; native navigation remains a release gate."""
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
class LocalRoutes(unittest.TestCase):
    def test_laptop_screen_exposes_real_local_destinations(self):
        view = (ROOT/'VoiceMatrix/RVCOnlineView.swift').read_text()
        for destination in ('CharacterLibraryView()', 'CharacterLibraryView(mode: .conversion)', 'RVCOnDeviceView()'):
            self.assertIn('NavigationLink { ' + destination + ' }', view)
        for identifier in ('rvc-local-speech', 'rvc-local-conversion', 'rvc-local-diagnostic'):
            self.assertIn(identifier, view)
    def test_copy_does_not_deny_existing_local_engines(self):
        view = (ROOT/'VoiceMatrix/RVCOnlineView.swift').read_text()
        studio = (ROOT/'VoiceMatrix/RVCOnlineStudio.swift').read_text()
        self.assertNotIn('Offline RVC and text-to-speech are unavailable', view)
        self.assertNotIn('Offline RVC and RVC text synthesis are not supported', studio)
        self.assertIn('not interchangeable with laptop RVC models', view)
    def test_local_routes_never_submit_audio(self):
        view = (ROOT/'VoiceMatrix/RVCOnlineView.swift').read_text()
        self.assertIn('Section("Use this iPhone instead")', view)
        section = view.split('Section("Use this iPhone instead")')[1].split('Section("1 · Choose a laptop model")')[0]
        self.assertNotIn('rvc.send', section)
        self.assertNotIn('rvc.retrySubmission', section)
if __name__ == '__main__': unittest.main()
