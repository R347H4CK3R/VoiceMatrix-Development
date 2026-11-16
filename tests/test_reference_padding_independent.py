from tools.test_shell import check_bash_syntax
import pathlib,unittest,yaml,subprocess,importlib.util,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
class IndependentTests(unittest.TestCase):
 def test_two_refs_strict_acceptance(self):
  s=(ROOT/'probes/reference-padding-independent/Diagnostic.swift').read_text()
  for v in ['for referenceID in ["8455-210777-0028","1580-141083-0051"]','for tailMilliseconds in [0,50]','F5ReferenceEngine(steps:32,seed:0)','wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash','referenceAudio:variant','independent-attempts.json']:self.assertIn(v,s)
 def test_workflow_readonly_bound_and_shell(self):
  w=yaml.safe_load((ROOT/'.github/workflows/reference-padding-independent.yml').read_text());self.assertEqual(w['permissions'],dict(contents='read',actions='read'));self.assertEqual(w['jobs']['actual-local-pipeline']['timeout-minutes'],50)
  for step in w['jobs']['actual-local-pipeline']['steps']:
   if 'run' in step:check_bash_syntax(step['run'])
 def test_bad_archive_preserved_rejected(self):
  spec=importlib.util.spec_from_file_location('prep',ROOT/'probes/reference-padding-independent/prepare.py');p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);(root/'prior.zip').write_bytes(b'bad')
   with self.assertRaises(AssertionError):p.prepare(root)
   self.assertEqual(list(root.iterdir()),[root/'prior.zip']);self.assertEqual((root/'prior.zip').read_bytes(),b'bad')
