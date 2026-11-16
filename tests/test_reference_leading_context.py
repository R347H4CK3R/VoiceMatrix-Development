import pathlib,unittest,shutil,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ReferenceContextTests(unittest.TestCase):
 def test_reference_entrypoint_only(self):
  s=(ROOT/'VoiceMatrix/OnDeviceTranscription.swift').read_text();self.assertIn('func transcribeReference(',s)
  studio=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text();self.assertIn('transcriber.transcribeReference(reference)',studio);self.assertIn('transcriber.transcribe(preview)',studio)
  self.assertIn('referenceContext: false',s);self.assertIn('referenceContext: true',s);self.assertIn('if !referenceContext && !LocalStudioEvidence.usableTranscript(text)',s)
 def test_reference_reads_are_bounded_and_complete(self):
  s=(ROOT/'VoiceMatrix/OnDeviceTranscription.swift').read_text()
  section=s[s.index('nonisolated static func referenceLeadingBuffer('):s.index('private nonisolated static func recoveryBuffer(')]
  self.assertIn('readReferenceFrames(format:',section)
  self.assertIn('while completed < frameCount',section)
  self.assertIn('min(4096, frameCount - completed)',section)
  self.assertIn('chunk.frameLength > 0, chunk.frameLength <= requested',section)
  self.assertIn('try Task.checkCancellation()',section)
  self.assertIn('guard completed == frameCount',section)
 def test_policy_bounds_executed(self):
  compiler=shutil.which('swiftc')
  if not compiler:self.skipTest('Swift unavailable')
  with tempfile.TemporaryDirectory() as d:
   binary=str(pathlib.Path(d)/'check');subprocess.run([compiler,str(ROOT/'VoiceMatrix/BundledASRPolicy.swift'),str(ROOT/'tests/native/ReferenceLeadingContextChecks.swift'),'-o',binary],check=True,timeout=60);subprocess.run([binary],check=True,timeout=10)
 def test_evidence_and_preservation(self):
  s=(ROOT/'VoiceMatrix/OnDeviceTranscription.swift').read_text();self.assertIn('let referenceLeadingSeconds: Double?',s);self.assertIn('referenceLeadingSeconds = Double(leadingFrames) / rate',s);self.assertIn('referenceLeadingSeconds: referenceLeadingSeconds',s);self.assertIn('inputDigest(file, byteCount: size, matching: inputSHA256)',s);self.assertIn('manager.transcribe(file, decoderState: &decoder)',s)
if __name__=='__main__':unittest.main()
