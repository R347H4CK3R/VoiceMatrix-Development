"""Preview package is monotonic, inspected and never implicitly released."""
import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class PreviewBuildTests(unittest.TestCase):
 def test_current_identity_after_historical_build12(self):
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  self.assertEqual(str(project['settings']['base']['CURRENT_PROJECT_VERSION']),'15')
  self.assertEqual(str(project['settings']['base']['MARKETING_VERSION']),'0.4.12')
 def test_inspected_source_bound_package(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build13.yml').read_text())
  self.assertEqual(w['permissions']['contents'],'read')
  self.assertEqual(w['on']['push']['branches'],['preview/voicematrix-build13'])
  self.assertEqual(w['jobs']['ipa']['needs'],'resolve')
  steps=w['jobs']['ipa']['steps'];runs='\n'.join(s.get('run','') for s in steps)
  self.assertIn('--expected-build 13',runs)
  self.assertIn('0.4.10 --expected-build 13',runs)
  self.assertIn('VoiceMatrix-Source-Proof.json',runs)
  self.assertIn('physicalDeviceVerified=False',runs)
  self.assertIn('likenessVerified=False',runs)
  self.assertNotIn('gh release',runs)
  self.assertIn('cmp vendor-before.json vendor-after.json',runs)
  self.assertEqual(runs.count('cmp frozen/Package.resolved VoiceMatrix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),2)
  self.assertIn('shasum -a 256 -c frozen-package.sha256',runs)
  for s in steps:
   if s.get('uses')=='actions/download-artifact@v4':self.assertNotIn('run-id',s['with'])

 def test_runtime_uses_same_frozen_graph_without_mutating_dependency(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build13.yml').read_text());job=w['jobs']['native-pipeline']
  self.assertEqual(job['needs'],'resolve');steps=job['steps'];runs='\n'.join(s.get('run','') for s in steps)
  self.assertIn('cmp frozen/Package.resolved "$graph"',runs)
  self.assertIn('for reader in first second',runs)
  self.assertNotIn('diarizer-eof/apply.py',runs)
  self.assertIn('(deny network*)',runs)
  downloads=[s for s in steps if s.get('uses')=='actions/download-artifact@v4'];self.assertEqual(downloads[0]['with'],{'name':'Character-frozen-dependencies','path':'frozen'})

class FrozenDependencyGraphTests(unittest.TestCase):
 def test_package_and_full_route_share_the_exact_existing_frozen_graph(self):
  import re
  from tools.test_shell import check_bash_syntax
  package=yaml.safe_load((ROOT/'.github/workflows/iphone-build13.yml').read_text())
  route=yaml.safe_load((ROOT/'.github/workflows/reference-context-full-route.yml').read_text())
  route_run=next(s['run'] for s in route['jobs']['diagnostic']['steps'] if s.get('name')=='Recover exact published-build frozen graph and retained licensed sources')
  resolve=package['jobs']['resolve'];runs='\n'.join(s.get('run','') for s in resolve['steps'])
  artifact=re.search(r'gh api (repos/\S+/actions/artifacts/\d+/zip)\s*> frozen.zip',route_run).group(1)
  checksum=re.search(r"echo '([a-f0-9]{64})  frozen.zip'",route_run).group(1)
  self.assertIn('gh api '+artifact+' > frozen.zip',runs)
  self.assertIn("echo '"+checksum+"  frozen.zip' | shasum -a 256 -c -",runs)
  self.assertIn("assert z.namelist()==['Package.resolved']",runs)
  self.assertIn("pathlib.Path('frozen/Package.resolved').write_bytes(z.read('Package.resolved'))",runs)
  self.assertIn('cp frozen/Package.resolved Package.resolved',runs)
  self.assertNotIn('xcodebuild',runs,'Resolve must recover the already verified graph, not resolve newer transitive versions')
  self.assertNotIn('xcodegen',runs)
  fetch=next(s for s in resolve['steps'] if 'gh api '+artifact in s.get('run',''))
  self.assertEqual(fetch['env']['GH_TOKEN'],'${{ github.token }}')
  upload=next(s for s in resolve['steps'] if s.get('uses')=='actions/upload-artifact@v4')
  self.assertEqual(upload['with']['name'],'Character-frozen-dependencies')
  self.assertEqual(upload['with']['path'],'Package.resolved')
  for step in resolve['steps']:
   if 'run' in step:check_bash_syntax(step['run'])

