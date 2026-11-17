"""Preview package is monotonic, inspected and never implicitly released."""
import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class PreviewBuildTests(unittest.TestCase):
 def test_current_identity_after_historical_build12(self):
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  self.assertEqual(str(project['settings']['base']['CURRENT_PROJECT_VERSION']),'16')
  self.assertEqual(str(project['settings']['base']['MARKETING_VERSION']),'0.4.13')
 def test_inspected_source_bound_package(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build14.yml').read_text())
  self.assertEqual(w['permissions']['contents'],'read')
  self.assertEqual(w['on']['push']['branches'],['preview/voicematrix-build14','feature/voicematrix-ondevice-ytdlp'])
  self.assertEqual(w['jobs']['ipa']['needs'],'resolve')
  steps=w['jobs']['ipa']['steps'];runs='\n'.join(s.get('run','') for s in steps)
  self.assertIn('--expected-build 14',runs)
  self.assertIn('0.4.11 --expected-build 14',runs)
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
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build14.yml').read_text());job=w['jobs']['native-pipeline']
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
  package=yaml.safe_load((ROOT/'.github/workflows/iphone-build14.yml').read_text())
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


class CombinedReleaseIdentityTests(unittest.TestCase):
 def test_version_and_current_notes_include_actual_resolver(self):
  project=yaml.safe_load((ROOT/'project.yml').read_text())['settings']['base']
  self.assertEqual(str(project['MARKETING_VERSION']),'0.4.13')
  self.assertEqual(str(project['CURRENT_PROJECT_VERSION']),'16')
  self.assertGreater(tuple(map(int,str(project['MARKETING_VERSION']).split('.'))),(0,4,9))
  app=(ROOT/'VoiceMatrix/App.swift').read_text()
  self.assertIn('What’s new · 0.4.13 (16)',app)
  self.assertIn('on-device yt-dlp resolver',app)
  self.assertIn('Some sources remain unsupported',app)
 def test_actual_python_bundle_is_checked_before_ipa_creation(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build14.yml').read_text())
  run='\n'.join(x.get('run','') for x in w['jobs']['ipa']['steps'])
  self.assertLess(run.index('verify_python_bundle.py Payload/VoiceMatrix.app'),run.index('tools/package_ipa.py Payload'))
 def test_artifact_contract_includes_independent_python_receipt(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build14.yml').read_text())
  upload=next(s for s in w['jobs']['ipa']['steps'] if s.get('uses')=='actions/upload-artifact@v4')
  self.assertEqual(set(upload['with']['path'].split()),{'VoiceMatrix-0.4.11-build14.ipa','python-runtime-inspection.json','python-runtime-inspection.log','character-inspection.json','character-ipa.sha256','source-proof.json','dependency-notices.json','assets.json','packaging-status.json','vendor-before.json','vendor-after.json'})
  run='\n'.join(x.get('run','') for x in w['jobs']['ipa']['steps'])
  self.assertIn('--json-out python-runtime-inspection.json',run)
