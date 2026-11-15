import pathlib,unittest,yaml,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
class FormatTests(unittest.TestCase):
 def test_words_unchanged_and_reference_receipt(self):
  s=(ROOT/'probes/reference-text-format/Diagnostic.swift').read_text()
  for v in ['LocalStudioEvidence.wordErrorRate(expected:originalText,actual:formattedText)==0','for textFormat in ["original","sentence"]','referenceRoot.appendingPathComponent("reference.wav")','recognizer.transcribe(url)','F5ReferenceEngine(steps:32,seed:0)','wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash','referenceText:refText','let failed=ReferenceReceipt','throw error']:self.assertIn(v,s)
  self.assertNotIn('reference-tail-',s)
 def test_readonly_bounded_and_shell(self):
  w=yaml.safe_load((ROOT/'.github/workflows/reference-text-format.yml').read_text());self.assertEqual(w['permissions'],dict(contents='read',actions='read'));self.assertEqual(w['jobs']['actual-local-pipeline']['timeout-minutes'],50)
  for step in w['jobs']['actual-local-pipeline']['steps']:
   if 'run' in step:subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)
