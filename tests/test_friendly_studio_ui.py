"""Source-level UI contract; native XCTest owns interaction/layout verification."""
import unittest
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
class FriendlyStudioUI(unittest.TestCase):
    def test_video_hero_and_plain_steps(self):
        app = (ROOT/'VoiceMatrix/App.swift').read_text()
        self.assertIn('HomeCard(title: "Make a voice from video"', app)
        for label in ('Add video', 'Pick clips', 'Try voice'):
            self.assertIn('"'+label+'"', app)
        self.assertIn('.accessibilityIdentifier("local-video-studio")', app)
    def test_technical_detail_and_logs_are_opt_in(self):
        view = (ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
        self.assertIn('DisclosureGroup("What this can do")', view)
        self.assertIn('DisclosureGroup {\n                    TimelineView', view)
        self.assertIn('Text("Processing details").accessibilityIdentifier("local-video-log-toggle")', view)
        self.assertIn('Analysis uses the MP4 companion', view)
    def test_authorization_and_inputs_remain_explicit(self):
        view = (ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
        self.assertIn('I have permission to use this video or audio and its voices', view)
        self.assertIn('StudioPasteButton { values in', view)
        native = (ROOT/'VoiceMatrix/StudioNativeInputs.swift').read_text()
        self.assertIn('class PasteControl: UIPasteControl', native)
        self.assertIn('itemProviders.count == 1', native)
        self.assertIn('self.generation == request', native)
        self.assertNotIn('traits.remove(.notEnabled)', native)
        self.assertIn('greaterThanOrEqualToConstant: 48', native)
        self.assertNotIn('UIPasteboard.general', native)
        self.assertIn('.accessibilityLabel("Video link")', view)
        for identifier in ('local-video-import','local-video-url','local-video-paste','local-video-authorization','local-video-generate','local-video-download','local-video-live-log','local-video-durable-log'):
            self.assertIn('"'+identifier+'"', view)
        self.assertIn('selected == nil || !authorized || local.busy', view)
        self.assertIn('isEmpty || !authorized || local.busy', view)
    def test_touch_and_scaling_contract(self):
        app = (ROOT/'VoiceMatrix/App.swift').read_text()
        self.assertIn('struct StudioSteps: View', app)
        self.assertIn('ViewThatFits(in: .horizontal)', app)
        self.assertIn('@ScaledMetric(relativeTo: .caption)', app)
        self.assertIn('steps(horizontal: false)', app)
        view = (ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
        self.assertIn('.frame(minHeight: 44)', view)
        self.assertNotIn('.minimumScaleFactor', view)

    def test_filled_actions_have_white_text_contrast(self):
        app = (ROOT/'VoiceMatrix/App.swift').read_text()
        color = re.search(r'static let action = Color\(red: ([0-9.]+), green: ([0-9.]+), blue: ([0-9.]+)\)', app)
        self.assertIsNotNone(color, 'Filled actions need a distinct high-contrast fill')
        rgb = list(map(float, color.groups()))
        linear = [v/12.92 if v<=0.04045 else ((v+0.055)/1.055)**2.4 for v in rgb]
        luminance = sum(a*b for a,b in zip(linear, [0.2126,0.7152,0.0722]))
        self.assertGreaterEqual(1.05/(luminance+0.05), 4.5)
        view = (ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
        self.assertEqual(view.count('.tint(StudioPalette.action)'), 3)
