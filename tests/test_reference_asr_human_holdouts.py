import copy,hashlib,importlib.util,io,json,pathlib,shutil,subprocess,tempfile,unittest,wave
ROOT=pathlib.Path(__file__).resolve().parents[1];PATH=ROOT/'probes/reference-asr-human-holdouts/prepare.py'
def module():
 s=importlib.util.spec_from_file_location('human_padding',PATH);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class HumanHoldoutTests(unittest.TestCase):
 def test_implementation_exists(self):self.assertTrue(PATH.is_file(),'Independent human preparation not implemented')
 def test_predeclared_four_new_speakers(self):
  m=module();rows=m.sources();self.assertEqual([r['offset'] for r in rows],[100,300,1200,1700]);self.assertEqual(len({r['speaker_id'] for r in rows}),4)
  self.assertTrue({r['speaker_id'] for r in rows}.isdisjoint({2961,4507,8455,1580}))
  self.assertEqual(m.VARIANTS,[('original',0,0),('leading250',.25,0)])
  self.assertTrue(all(r['license']=='CC-BY-4.0' and r['sourceFrames']==round(r['duration']*16000) for r in rows))
 def test_row_pins_identity_text_and_revision(self):
  m=module();s=m.sources()[0];row=dict(id=s['id'],speaker_id=s['speaker_id'],text=s['referenceText'],audio=[dict(src=s['audioAssetPath']+'?signed=1')]);self.assertEqual(m.validate_row(row,s),row['audio'][0]['src'])
  for key,value in [('id','changed'),('text','ASR replacement'),('speaker_id',1),('audio',[dict(src='https://example.com/x')])]:
   bad=copy.deepcopy(row);bad[key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):m.validate_row(bad,s)
 def test_source_bytes_pinned(self):
  m=module();raw=b'full source';s={'sourceSHA256':hashlib.sha256(raw).hexdigest(),'sourceBytes':len(raw)};m.validate_source(raw,s)
  with self.assertRaises(ValueError):m.validate_source(raw+b'x',s)
 @unittest.skipUnless(shutil.which('ffmpeg'),'ffmpeg unavailable')
 def test_decode_entire_source_and_only_two_cases(self):
  m=module()
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);input=p/'in.wav'
   with wave.open(str(input),'wb') as w:w.setparams((1,2,16000,0,'NONE','none'));w.writeframes(b'\x01\x02'*32000)
   flac=p/'source.flac';subprocess.run(['ffmpeg','-v','error','-i',str(input),str(flac)],check=True)
   source=dict(id='fixture-1',sourceFrames=32000,sampleRate='16000',referenceText='EXACT CORPUS WORDS',sourceSHA256=hashlib.sha256(flac.read_bytes()).hexdigest())
   raw=m.decode_complete(flac,p/'full.wav',source)
   with wave.open(io.BytesIO(raw)) as w:self.assertEqual(w.getnframes(),48000)
   cases=m.make_cases(raw,source,p)
   self.assertEqual(len(cases),2)
   for c in cases:self.assertEqual(c['expected'],'EXACT CORPUS WORDS');self.assertEqual(c['sourceFrames'],48000)
   with wave.open(str(p/cases[1]['file'])) as w:self.assertEqual(w.getnframes(),54000);self.assertEqual(w.readframes(6000),bytes(12000))
   bad=dict(source,sourceFrames=31999)
   with self.assertRaises(ValueError):m.decode_complete(flac,p/'bad.wav',bad)
if __name__=='__main__':unittest.main()

class WorkflowContractTests(unittest.TestCase):
 def test_workflow_cli_and_original_recognizer(self):
  import yaml,shlex
  workflow=yaml.safe_load((ROOT/'.github/workflows/reference-asr-human-holdouts.yml').read_text())
  lines=[s.strip() for step in workflow['jobs']['diagnose']['steps'] for s in step.get('run','').splitlines()]
  self.assertIn('python3 -m pip install -r tests/requirements-native.txt',lines)
  command=next(s for s in lines if s.startswith('python3 probes/reference-asr-human-holdouts/prepare.py'))
  self.assertEqual(shlex.split(command),['python3','probes/reference-asr-human-holdouts/prepare.py','padding-evidence'])
  self.assertTrue((ROOT/'probes/reference-asr-leading-padding/prepare.py').is_file())
  probe=(ROOT/'probes/reference-asr-human-holdouts/Sources/Probe/Probe.swift').read_text()
  self.assertIn('manifest.cases.count == 8',probe)
  self.assertIn('recognizer.transcribe(file)',probe)
  self.assertNotIn('transcribe(file,',probe)
