import json,pathlib,subprocess,sys,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CoreMLGroupEvaluationTests(unittest.TestCase):
 def check(self,groups):
  with tempfile.TemporaryDirectory() as temp:
   p=pathlib.Path(temp);(p/'a.json').write_text(json.dumps({'speakerWindows':groups}));(p/'f.json').write_text(json.dumps({'truth':[{'speaker':'A','start':0,'end':10},{'speaker':'B','start':11,'end':21}]}))
   return subprocess.run([sys.executable,str(ROOT/'probes/coreml-real-speakers/check.py'),str(p/'a.json'),str(p/'f.json')],capture_output=True).returncode
 def test_separate_anonymous_groups_pass(self):
  self.assertEqual(self.check([{'speaker':'x','windows':[{'start':1,'end':5}]},{'speaker':'y','windows':[{'start':12,'end':16}]}]),0)
 def test_one_group_for_both_voices_fails(self):
  self.assertNotEqual(self.check([{'speaker':'x','windows':[{'start':1,'end':5},{'start':12,'end':16}]}]),0)
 def test_crossing_a_speaker_boundary_fails(self):
  self.assertNotEqual(self.check([{'speaker':'x','windows':[{'start':8,'end':13}]}]),0)
 def test_missing_speaker_fails(self):
  self.assertNotEqual(self.check([{'speaker':'x','windows':[{'start':1,'end':5}]}]),0)
