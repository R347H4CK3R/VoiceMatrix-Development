import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Diagnostics(unittest.TestCase):
 def test_failure_evidence_and_success_evidence_precede_assertions(self):
  s=(ROOT/'probes/clip-speaker-review/Sources/Probe/Probe.swift').read_text()
  self.assertIn('let originalError = error',s)
  self.assertIn('throw originalError',s)
  self.assertIn('reviewStore.snapshot(for: clip)',s)
  self.assertIn('LocalSpeakerDiarization.analyze(source: snapshot',s)
  self.assertIn('defer { try? FileManager.default.removeItem(at: snapshot) }',s)
  self.assertIn('"-diagnostic-analysis.json"',s)
  self.assertIn('fflush(stdout)',s)
  self.assertLess(s.index('item.name + "-analysis.json"'),s.index('try reviewStore.validate(analysis'))
  for term in ['expectedFrames','analysis.seconds','clip.sha256','sourceSHA256','selectionPolicyVersion']:self.assertIn(term,s)
  for term in ['two-speaker clip did not recover two groups','overlap clip not flagged','silence invented speakers']:self.assertIn(term,s)
if __name__=='__main__':unittest.main()
