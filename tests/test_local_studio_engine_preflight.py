"""Check source ordering so unavailable builds fail before acquisition or processing."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class LocalStudioEnginePreflightTests(unittest.TestCase):
 def test_engine_requirement_precedes_media_acquisition(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  run=s[s.index('    private func run(source:'):]
  preflight=run.index('guard let bundle = f5Bundle else { throw LocalError.engine }')
  self.assertLess(preflight, run.index('library.beginLocalGeneration()'))
  self.assertLess(preflight, run.index('LocalMediaAcquisition.acquire('))
  self.assertLess(preflight, run.index('if let source'))
  self.assertEqual(run.count('guard let bundle = f5Bundle'),1)
