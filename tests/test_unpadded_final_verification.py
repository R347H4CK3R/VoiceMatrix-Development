import copy,hashlib,importlib.util,json,pathlib,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];PATH=ROOT/'probes/leading-padding-unpadded-verifier/stage.py'
def module():
 s=importlib.util.spec_from_file_location('unpadded_stage',PATH);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class UnpaddedTests(unittest.TestCase):
 def test_exists(self):self.assertTrue(PATH.is_file(),'Unpadded final verifier missing')
 def test_exact_two_files_hash_and_safe_names(self):
  m=module()
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'work').mkdir();rows=[]
   for i in range(2):
    data=f'wav{i}'.encode();(p/'work'/f'out{i}.wav').write_bytes(data);rows.append(dict(voiceID=f'voice{i}',file=f'out{i}.wav',newSpeechSHA256=hashlib.sha256(data).hexdigest()))
   report=dict(newSpeeches=rows,importedIDs=['voice0','voice1']);self.assertEqual(len(m.validate(p,report)),2)
   bads=[dict(report,newSpeeches=rows[:1]),dict(report,newSpeeches=rows+[rows[0]])]
   for key,val in [('file','../out0.wav'),('file','x\\out.wav'),('newSpeechSHA256','0'*64),('voiceID','voice0')]:
    b=copy.deepcopy(report);b['newSpeeches'][1][key]=val;bads.append(b)
   for b in bads:
    with self.assertRaises(ValueError):m.validate(p,b)
 def test_source_pins_and_no_staged_wrapper(self):
  m=module()
  for name,sha in m.SOURCE_PINS.items():self.assertEqual(hashlib.sha256(((ROOT/'probes/leading-padding-unpadded-verifier/Baseline'/name) if name in ('OnDeviceTranscription.swift','BundledASRPolicy.swift') else ROOT/'VoiceMatrix'/name).read_bytes()).hexdigest(),sha)
  s=(ROOT/'probes/leading-padding-unpadded-verifier/Sources/Probe/Probe.swift').read_text()
  for needle in ['recognizer.transcribe(file)','wordErrorRate','== 0','outcomes.count == 2','inputSHA256 == item.sha256','options: .atomic']:
   self.assertIn(needle,s)
  self.assertNotIn('diagnosticLeadingBuffer',s)
  self.assertIn('.package(path: "../../Vendors/FluidAudio")',(ROOT/'probes/leading-padding-unpadded-verifier/Package.swift').read_text())
if __name__=='__main__':unittest.main()
