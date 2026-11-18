"""Wiring gates; native XCTest verifies the actual Swift adapter behavior."""
import pathlib,unittest
R=pathlib.Path(__file__).resolve().parents[1]
class Route(unittest.TestCase):
 def test_iphone_uses_resolver_before_native_download(self):
  s=(R/'VoiceMatrix/LocalMediaAcquisition.swift').read_text()
  self.assertIn('OnDeviceYouTubeResolver.shared.resolve',s)
  ios=s.split('#if os(iOS)',1)[1].split('#else',1)[0]
  self.assertIn('resolveYouTubePlan',ios)
  self.assertNotIn('Transfer.download',ios)
  self.assertNotIn('youtubePlan(Data',ios)
 def test_adapter_checks_native_media_boundary(self):
  s=(R/'VoiceMatrix/OnDeviceYouTubeResolver.swift').read_text()
  for required in ['LocalMediaURLPolicy.validate','withTaskCancellationHandler','CancellationError','maximumBytes','cancelRequest','schemaVersion']:
   self.assertIn(required,s)
