import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class EOFRecoveryWorkflowTests(unittest.TestCase):
    def test_same_real_fixture_and_pipeline_acceptance(self):
        old=yaml.safe_load((ROOT/'.github/workflows/real-reference-pool.yml').read_text())
        new=yaml.safe_load((ROOT/'.github/workflows/real-reference-pool-eof.yml').read_text())
        self.assertEqual(old['permissions'],new['permissions'])
        a=old['jobs']['actual-local-pipeline'];b=new['jobs']['actual-local-pipeline']
        self.assertEqual(a['timeout-minutes'],b['timeout-minutes'])
        for i in [0,1,2,3,5]:
            self.assertEqual(a['steps'][i],b['steps'][i])
        self.assertEqual(new['on']['push']['branches'],['diagnostic/real-reference-pool-eof'])
    def test_exact_patch_proof_applied_between_resolve_and_build(self):
        w=yaml.safe_load((ROOT/'.github/workflows/real-reference-pool-eof.yml').read_text())
        s=w['jobs']['actual-local-pipeline']['steps'][4]['run']
        self.assertLess(s.index('cp "$graph" local-evidence/Package.resolved'),s.index('python3 probes/diarizer-eof/apply.py'))
        self.assertLess(s.index('python3 probes/diarizer-eof/apply.py'),s.index('CODE_SIGNING_ALLOWED=NO'))
        self.assertIn("hexdigest()==h['after']",s)
        self.assertIn('cmp local-evidence/Package.resolved',s)
        self.assertIn('diagnostic-hash-patched-independently-resolved',s)
