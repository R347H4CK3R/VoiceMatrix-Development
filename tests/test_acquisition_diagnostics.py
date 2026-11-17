"""Wiring contracts; native tests exercise actual failure classification."""
import pathlib, unittest
R=pathlib.Path(__file__).resolve().parents[1]
class Diagnostics(unittest.TestCase):
 def test_http_and_network_are_not_collapsed(self):
  s=(R/'VoiceMatrix/LocalMediaAcquisition.swift').read_text()
  for value in ['Failure.httpStatus(http.statusCode)', 'Failure.network(network.code.rawValue)', 'Failure.incomplete', 'Failure.bounds']:
   self.assertIn(value,s)
 def test_player_without_direct_urls_is_actionable(self):
  s=(R/'VoiceMatrix/LocalMediaURLPolicy.swift').read_text()
  self.assertIn('throw Failure.noDirectStreams',s)
 def test_local_import_fallback(self):
  s=(R/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  self.assertIn('Import an authorized local file instead',s)
  self.assertIn('local-video-import-fallback',s)
