import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Wiring(unittest.TestCase):
 def test_isolated_copy_and_bounded_stage_evidence(self):
  p=(ROOT/'probes/clip-speaker-controls/Package.swift').read_text();s=(ROOT/'probes/clip-speaker-controls/Sources/Probe/Probe.swift').read_text();w=(ROOT/'.github/workflows/clip-speaker-controls.yml').read_text()
  self.assertIn('VOICEMATRIX_DIAGNOSTIC_FLUIDAUDIO_PATH',p)
  self.assertIn('instrument_stages.py',w)
  self.assertIn('struct StageExport: Decodable',s)
  self.assertIn('maximumBytes: 262_144',s)
  self.assertIn('stageStatistics',s)
  self.assertNotIn('clustering.threshold =',s)
if __name__=='__main__':unittest.main()
