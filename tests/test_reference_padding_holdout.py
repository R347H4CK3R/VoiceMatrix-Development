from tools.test_shell import check_bash_syntax
import pathlib,unittest,yaml,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
class HoldoutTests(unittest.TestCase):
 def test_bounded_pair_and_strict_acceptance(self):
  s=(ROOT/'probes/reference-padding-holdout/Diagnostic.swift').read_text()
  for v in ['for (caseID,expected) in texts.enumerated()','for tailMilliseconds in [0,50]','F5ReferenceEngine(steps:32,seed:0)','wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash','Attempt(caseID:caseID,tailMilliseconds:','holdout-attempts.json']:self.assertIn(v,s)
 def test_workflow_preserves_references_and_distinct_outputs(self):
  w=yaml.safe_load((ROOT/'.github/workflows/reference-padding-holdout.yml').read_text());self.assertEqual(w['permissions'],dict(contents='read',actions='read'))
  scripts=[s['run'] for s in w['jobs']['actual-local-pipeline']['steps'] if 'run' in s]
  for s in scripts:check_bash_syntax(s)
  self.assertIn('[(c,t) for c in range(3) for t in [0,50]]','\n'.join(scripts))
