import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class PairTests(unittest.TestCase):
 def test_only_conditioning_word_is_added(self):
  s=(ROOT/'probes/two-reader-transcript-pair/Diagnostic.swift').read_text()
  self.assertIn('variant == "original" ? originalRefText : "And " + originalRefText',s)
  self.assertNotIn('lowercased()',s)
  for x in ['for seed:UInt64 in [0]','F5ReferenceEngine(steps:32,seed:seed)','wer<=0.1','recognizer.lastEvidence?.inputSHA256==hash','preserveIncomplete:true','variant:variant,referenceText:refText']:
   self.assertIn(x,s)
 def test_separate_processes_frozen_build_and_retained_control(self):
  old=yaml.safe_load((ROOT/'.github/workflows/two-reader-replay.yml').read_text());w=yaml.safe_load((ROOT/'.github/workflows/two-reader-transcript-pair.yml').read_text())
  self.assertEqual(w['permissions'],{'contents':'read','actions':'read'})
  self.assertEqual(w['jobs']['diagnostic']['steps'][7],old['jobs']['diagnostic']['steps'][7])
  s=w['jobs']['diagnostic']['steps'][8]['run']
  self.assertIn('for variant in original with-And; do',s);self.assertIn('(deny network*)',s);self.assertIn("'And '+original",s)
