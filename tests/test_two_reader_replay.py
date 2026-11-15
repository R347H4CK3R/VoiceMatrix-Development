import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ReplayTests(unittest.TestCase):
 def test_exact_input_single_seed_and_unchanged_acceptance(self):
  s=(ROOT/'probes/two-reader-replay/Diagnostic.swift').read_text()
  for v in ['fd0049197b44f2ab96cf5ae077b6b8a5081435a54463d94fe2b04f2fdeda90a7','for seed:UInt64 in [0]','F5ReferenceEngine(steps:32,seed:seed)','wer<=0.1','recognizer.lastEvidence?.inputSHA256==hash','preserveIncomplete:true','Then we insist upon it']:
   self.assertIn(v,s)
  self.assertNotIn('trim',s[s.index('static func main'):].lower())
 def test_reuses_frozen_vendor_build_and_readonly_networkdenied_execution(self):
  old=yaml.safe_load((ROOT/'.github/workflows/two-complete-readers.yml').read_text());new=yaml.safe_load((ROOT/'.github/workflows/two-reader-replay.yml').read_text())
  self.assertEqual(new['permissions'],{'contents':'read','actions':'read'})
  self.assertEqual(new['jobs']['diagnostic']['steps'][7],old['jobs']['diagnostic']['steps'][7])
  self.assertIn('(deny network*)',new['jobs']['diagnostic']['steps'][8]['run'])
  self.assertIn('job success does not imply speech acceptance',new['jobs']['diagnostic']['steps'][8]['run'])
