import pathlib,unittest
class RunAll(unittest.TestCase):
 def test_each_case_records_failure_then_checks_preservation_before_final_failure(self):
  text=(pathlib.Path(__file__).resolve().parents[1]/'probes/clip-speaker-review/Sources/Probe/Probe.swift').read_text()
  self.assertIn('var failures: [String] = []',text)
  self.assertIn('for (url, expected) in originals',text)
  self.assertIn('failures.append',text)
  self.assertIn('if !failures.isEmpty',text)
  self.assertLess(text.index('for (url, expected) in originals'),text.index('if !failures.isEmpty'))
  for check in ['two-speaker clip did not recover two groups','overlap clip not flagged','silence invented speakers','throw originalError']:self.assertIn(check,text)
if __name__=='__main__':unittest.main()
