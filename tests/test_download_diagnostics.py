"""Static route checks only; actual Swift behavior is covered by native XCTest."""
import pathlib,unittest
R=pathlib.Path(__file__).resolve().parents[1]
class DownloadDiagnostics(unittest.TestCase):
 def test_media_html_rejection_is_distinct_without_acceptance_change(self):
  s=(R/'VoiceMatrix/LocalMediaAcquisition.swift').read_text()
  self.assertIn('Failure.mediaHTML',s)
  self.assertIn('Failure.mediaType',s)
  self.assertIn('guard acceptable else',s)
 def test_fixed_resolver_failure_mapping(self):
  s=(R/'VoiceMatrix/OnDeviceYouTubeResolver.swift').read_text()
  self.assertIn('case "network_unavailable": throw LocalMediaURLPolicy.Failure.resolverNetwork',s)
  self.assertIn('case "source_unavailable": throw LocalMediaURLPolicy.Failure.resolverSource',s)
 def test_codes_are_fixed_and_message_does_not_echo_source(self):
  s=(R/'VoiceMatrix/LocalMediaURLPolicy.swift').read_text()
  for code in ['[media-html]','[media-type]','[resolver-network]','[resolver-source]','[resolver-engine]']:
   self.assertIn(code,s)
