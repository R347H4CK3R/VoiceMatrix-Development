import hashlib,json,pathlib,subprocess,tempfile,unittest,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Controls(unittest.TestCase):
 def test_probe_saves_precluster_masks_and_preserves_production_config(self):
  s=(ROOT/'probes/clip-speaker-controls/Sources/Probe/Probe.swift').read_text()
  self.assertLess(s.index('evidence.segmentation = try MaskEvidence'),s.index('let diagnostic = try manager.cluster'))
  self.assertLess(s.index('evidence.embeddingCount = prepared.embeddingCount'),s.index('let diagnostic = try manager.cluster'))
  self.assertIn('catch OfflineDiarizationError.noSpeechDetected',s)
  self.assertIn('evidence.productionSegments == evidence.diagnosticSegments',s)
  self.assertIn('for item in manifest.cases',s)
  self.assertIn('try require(failures.isEmpty',s)
  self.assertNotIn('config.clustering.',s)
  self.assertIn('defer { try? FileManager.default.removeItem(at: rawExport) }',s)
 def test_fixed_controls_and_original_bytes(self):
  with tempfile.TemporaryDirectory() as tmp:
   root=pathlib.Path(tmp)
   subprocess.run(['python3',str(ROOT/'probes/clip-speaker-controls/prepare.py'),str(root/'controls')],check=True)
   subprocess.run(['python3',str(ROOT/'probes/clip-speaker-review/prepare.py'),str(root/'original')],check=True)
   manifest=json.loads((root/'controls/fixture.json').read_text()); cases={c['name']:c for c in manifest['cases']}
   self.assertEqual(len(cases),15)
   for p in (root/'original').glob('*.wav'):self.assertEqual(p.read_bytes(),(root/'controls'/p.name).read_bytes())
   for case in cases.values():
    p=root/'controls'/(case['name']+'.wav')
    self.assertEqual(hashlib.sha256(p.read_bytes()).hexdigest(),case['audioSHA256'])
   for id in ['1320','7729','4446','3729']:
    with wave.open(str(root/'controls'/('same-'+id+'.wav'))) as f:
     pcm=f.readframes(f.getnframes());self.assertEqual(len(pcm),7*32000)
     self.assertEqual(pcm[:96000],pcm[128000:]);self.assertEqual(pcm[96000:128000],bytes(32000))
   for name in ['pair-1320-7729','pair-4446-3729']:
    self.assertEqual(cases[name]['seconds'],7)
    self.assertEqual(cases[name+'-no-gap']['seconds'],6)
    _,a,b=name.split('-')
    def read(n):
     with wave.open(str(root/'controls'/(n+'.wav'))) as f:return f.readframes(f.getnframes())
    pa,pb=read('same-'+a)[:96000],read('same-'+b)[:96000]
    self.assertEqual(read(name),pa+bytes(32000)+pb)
    self.assertEqual(read(name+'-no-gap'),pa+pb)
if __name__=='__main__':unittest.main()
