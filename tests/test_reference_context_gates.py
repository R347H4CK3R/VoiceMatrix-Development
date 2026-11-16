import importlib.util,pathlib,unittest,tempfile,io,wave,hashlib,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
def module():
 p=ROOT/'probes/reference-context-human-holdouts/prepare.py';s=importlib.util.spec_from_file_location('context_prepare',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class ContextGatesTests(unittest.TestCase):
 def test_same_original_bytes_for_both_methods(self):
  m=module();b=io.BytesIO()
  with wave.open(b,'wb') as w:w.setparams((1,2,24000,0,'NONE','none'));w.writeframes(b'\x01\x02'*24000)
  raw=b.getvalue();source={'id':'1-2-3','referenceText':'Fixed corpus words','sourceSHA256':'a'*64}
  with tempfile.TemporaryDirectory() as d:
   cases=m.make_cases(raw,source,d)
   self.assertEqual([r.get('mode') for r in cases],['baseline','reference'])
   self.assertEqual(cases[0]['file'],cases[1]['file']);self.assertEqual((pathlib.Path(d)/cases[0]['file']).read_bytes(),raw)
   self.assertTrue(all(r['sha256']==hashlib.sha256(raw).hexdigest() for r in cases))
 def test_workflow_no_global_diagnostic_patch(self):
  w=yaml.safe_load((ROOT/'.github/workflows/reference-context-full-route.yml').read_text());runs='\n'.join(s.get('run','') for s in w['jobs']['diagnostic']['steps']);self.assertIn('xcodegen generate',runs);self.assertNotIn('padding-staged',runs);self.assertNotIn('diagnostic-leading.yml',runs)
  self.assertIn('probes/two-complete-readers/check.py',runs);self.assertIn('leading-padding-unpadded-verifier',runs)
 def test_holdout_strict_receipts_same_files_and_correct_cli(self):
  p=ROOT/'probes/reference-context-human-holdouts';s=(p/'Sources/Probe/Probe.swift').read_text()
  for required in ['recognizer.transcribeReference(file)','recognizer.transcribe(file)','referenceLeadingSeconds == expectedContext','wer == 0','results.allSatisfy({ $0.accepted })','groups.count == 4','Set(entries.map(\\.mode))','Set(entries.map(\\.sha256)).count == 1']:self.assertIn(required,s)
  w=yaml.safe_load((ROOT/'.github/workflows/reference-context-human-holdouts.yml').read_text());runs='\n'.join(x.get('run','') for x in w['jobs']['diagnose']['steps'])
  self.assertIn('python3 probes/reference-context-human-holdouts/prepare.py padding-evidence',runs);self.assertNotIn('padding-staged',runs)
  self.assertIn('(deny network*)',runs);self.assertEqual(w['permissions']['contents'],'read')
 def test_four_predeclared_new_humans(self):
  rows=module().sources();self.assertEqual([r['offset'] for r in rows],[100,300,1200,1700]);self.assertEqual(len({r['speaker_id'] for r in rows}),4)
