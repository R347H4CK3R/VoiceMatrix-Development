import pathlib,unittest,yaml,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SecondRouteTests(unittest.TestCase):
 def test_unchanged_diagnostic_and_strict_source(self):
  s=(ROOT/'probes/second-complete-speaker-route/prepare.py').read_text()
  self.assertIn("hashlib.sha256(raw).hexdigest()==src['sourceSHA256']",s)
  self.assertIn("4507-16021-0031",s);self.assertNotIn("'-ss'",s);self.assertNotIn("'-t'",s)
  w=yaml.safe_load((ROOT/'.github/workflows/second-complete-speaker-route.yml').read_text());self.assertEqual(w['permissions'],dict(contents='read',actions='read'))
  for step in w['jobs']['actual-local-pipeline']['steps']:
   if 'run' in step:
    subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)
    self.assertNotIn('original.write_bytes',step['run'])
  s='\n'.join(x.get('run','') for x in w['jobs']['actual-local-pipeline']['steps']);self.assertIn('audio local-evidence/transcript.txt',s);self.assertIn('(deny network*)',s)
