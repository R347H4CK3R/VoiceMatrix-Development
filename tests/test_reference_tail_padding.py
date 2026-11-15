import hashlib,importlib.util,pathlib,tempfile,unittest,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('padding',ROOT/'probes/reference-tail-padding/prepare.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
class PaddingTests(unittest.TestCase):
 def test_append_only_and_preserve_original(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);source=root/'reference.wav'
   with wave.open(str(source),'wb') as w:w.setparams((1,2,24000,0,'NONE','NONE'));w.writeframes(b'\x12\x34'*2400)
   original=source.read_bytes();old=p.SOURCE_SHA;p.SOURCE_SHA=hashlib.sha256(original).hexdigest()
   try:
    proof=p.prepare(root);self.assertEqual(source.read_bytes(),original);self.assertEqual((root/'reference-tail-0.wav').read_bytes(),original)
    with wave.open(str(root/'reference-tail-50.wav')) as w:self.assertEqual(w.readframes(w.getnframes()),b'\x12\x34'*2400+bytes(2400))
    self.assertEqual(proof['variants'][1]['addedFrames'],1200)
    with self.assertRaises(AssertionError):p.prepare(root)
    self.assertEqual(source.read_bytes(),original)
   finally:p.SOURCE_SHA=old
 def test_wrong_identity_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);(root/'reference.wav').write_bytes(b'wrong')
   with self.assertRaises(AssertionError):p.prepare(root)
   self.assertFalse((root/'reference-tail-0.wav').exists())
 def test_same_seed_strict_acceptance(self):
  s=(ROOT/'probes/reference-tail-padding/Diagnostic.swift').read_text()
  for required in ['for tailMilliseconds in [0,50]','F5ReferenceEngine(steps:32,seed:0)','wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash','referenceAudio:variant','rawOutputSHA256:try digest(raw)']:self.assertIn(required,s)
