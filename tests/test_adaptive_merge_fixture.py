"""Inspect deterministic media inputs; native XCTest still exercises the actual merger."""
import hashlib,json,pathlib,shutil,subprocess,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class AdaptiveMergeFixture(unittest.TestCase):
 def test_explicit_test_bundle_inputs_replace_unrelated_simulator_encoder(self):
  source=(ROOT/'VoiceMatrixTests/LocalMediaAcquisitionTests.swift').read_text().split('func testAdaptiveMergeRunsOnSyntheticLocalTracksAndPreservesOriginals()',1)[1].split('func testDownloadWritesExact',1)[0]
  self.assertNotIn('AVAssetWriter(',source)
  for name in ['adaptive-video.mp4','adaptive-audio.m4a']:
   self.assertTrue((ROOT/'tests/fixtures'/name).is_file())
   self.assertIn('tests/fixtures/'+name,(ROOT/'project.yml').read_text())
  for contract in ['LocalMediaAcquisition.merge','LocalMediaAcquisition.verify','maximumBytes:10_000_000','XCTAssertEqual(videoTracks.count,1)','XCTAssertEqual(audioTracks.count,1)','accuracy:0.1','Data(contentsOf:video),originalVideo','Data(contentsOf:audio),originalAudio']:
   self.assertIn(contract,source)
 def test_fixture_changes_trigger_both_native_gates(self):
  for name in ['ondevice-resolver-app','character-ui-smoke']:
   self.assertIn("'tests/fixtures/adaptive-*'",(ROOT/'.github/workflows'/(name+'.yml')).read_text())
 def test_pinned_synthetic_fixture_bytes(self):
  expected={'adaptive-video.mp4':'b0710067fc17fdad4b0d1ad426f4105a64139ab62f41d05f0572dcd3a14b087e','adaptive-audio.m4a':'40834af6eb24a2e0fb751703f65c003215960f44abf05ef7e134d2ca69104516'}
  for name,digest in expected.items():self.assertEqual(hashlib.sha256((ROOT/'tests/fixtures'/name).read_bytes()).hexdigest(),digest)
 def test_real_separate_tracks_are_complete_three_second_inputs(self):
  for name,kind in [('adaptive-video.mp4','video'),('adaptive-audio.m4a','audio')]:
   path=ROOT/'tests/fixtures'/name;self.assertTrue(path.is_file(),'Missing deterministic fixture')
   if not shutil.which('ffprobe'):self.skipTest('ffprobe unavailable; native fixture checks remain required')
   j=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)]))
   self.assertEqual(len(j['streams']),1);self.assertEqual(j['streams'][0]['codec_type'],kind)
   self.assertAlmostEqual(float(j['format']['duration']),3,delta=.01)
   self.assertLess(path.stat().st_size,100_000)

 def test_audio_fixture_has_no_lossy_encoder_priming(self):
  if not shutil.which('ffprobe'): self.skipTest('ffprobe unavailable')
  j=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_packets','-of','json',str(ROOT/'tests/fixtures/adaptive-audio.m4a')]))
  self.assertEqual(j['streams'][0]['codec_name'],'alac')
  self.assertEqual(float(j['packets'][0]['pts_time']),0)
  self.assertFalse(any(s.get('skip_samples',0) for p in j['packets'] for s in p.get('side_data_list',[])))
