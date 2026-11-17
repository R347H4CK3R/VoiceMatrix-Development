"""Wiring gates; native XCTest verifies the actual Swift adapter behavior."""
import pathlib,unittest
R=pathlib.Path(__file__).resolve().parents[1]
class Route(unittest.TestCase):
 def test_unsupported_page_routes_to_native_resolver(self):
  s=(R/'VoiceMatrix/LocalMediaAcquisition.swift').read_text()
  self.assertIn('OnDeviceYouTubeResolver.shared.resolve',s)
  self.assertIn('case .unsupported, .noDirectStreams:',s)
  self.assertIn('default: throw failure',s)
 def test_adapter_checks_native_media_boundary(self):
  s=(R/'VoiceMatrix/OnDeviceYouTubeResolver.swift').read_text()
  for required in ['LocalMediaURLPolicy.validate','withTaskCancellationHandler','CancellationError','maximumBytes','cancelRequest','schemaVersion']:
   self.assertIn(required,s)
