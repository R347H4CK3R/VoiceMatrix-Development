import pathlib,unittest,yaml,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
class BoundaryTests(unittest.TestCase):
 def test_actual_asr_and_strict_gates(self):
  s=(ROOT/'probes/reference-boundary-selection/Diagnostic.swift').read_text()
  for v in ['["2961-retained","2961-quiet-excerpt"]','let refText=referenceReceipt.recognized','referenceReceipt.wordErrorRate!<=0.1','referenceReceipt.evidence?.inputSHA256==referenceReceipt.inputSHA256','F5ReferenceEngine(steps:32,seed:0)','wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash']:self.assertIn(v,s)
  self.assertNotIn('uppercased()',s);self.assertNotIn('lowercased()',s)
 def test_readonly_and_shell(self):
  w=yaml.safe_load((ROOT/'.github/workflows/reference-boundary-selection.yml').read_text());self.assertEqual(w['permissions'],dict(contents='read',actions='read'))
  for step in w['jobs']['actual-local-pipeline']['steps']:
   if 'run' in step:subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)
