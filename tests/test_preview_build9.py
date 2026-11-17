"""Preview package is monotonic, inspected and never implicitly released."""
import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class PreviewBuildTests(unittest.TestCase):
 def test_current_identity_after_historical_build9(self):
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  self.assertEqual(str(project['settings']['base']['CURRENT_PROJECT_VERSION']),'15')
  self.assertEqual(str(project['settings']['base']['MARKETING_VERSION']),'0.4.12')
 def test_inspected_source_bound_package(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build9.yml').read_text())
  self.assertEqual(w['permissions']['contents'],'read')
  self.assertEqual(w['on']['push']['branches'],['preview/voicematrix-build9'])
  self.assertEqual(w['jobs']['ipa']['needs'],'resolve')
  steps=w['jobs']['ipa']['steps'];runs='\n'.join(s.get('run','') for s in steps)
  self.assertIn('--expected-build 9',runs)
  self.assertIn('0.4.9 --expected-build 9',runs)
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
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build9.yml').read_text());job=w['jobs']['native-pipeline']
  self.assertEqual(job['needs'],'resolve');steps=job['steps'];runs='\n'.join(s.get('run','') for s in steps)
  self.assertIn('cmp frozen/Package.resolved "$graph"',runs)
  self.assertIn('for reader in first second',runs)
  self.assertNotIn('diarizer-eof/apply.py',runs)
  self.assertIn('(deny network*)',runs)
  downloads=[s for s in steps if s.get('uses')=='actions/download-artifact@v4'];self.assertEqual(downloads[0]['with'],{'name':'Character-frozen-dependencies','path':'frozen'})
