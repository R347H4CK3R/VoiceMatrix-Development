"""Preview package is monotonic, inspected and never implicitly released."""
import pathlib,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class PreviewBuildTests(unittest.TestCase):
 def test_current_identity_after_historical_build8(self):
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  self.assertEqual(str(project['settings']['base']['CURRENT_PROJECT_VERSION']),'14')
  self.assertEqual(str(project['settings']['base']['MARKETING_VERSION']),'0.4.11')
 def test_inspected_source_bound_package(self):
  w=yaml.safe_load((ROOT/'.github/workflows/iphone-build8.yml').read_text())
  self.assertEqual(w['permissions']['contents'],'read')
  self.assertEqual(w['on']['push']['branches'],['preview/voicematrix-build8'])
  self.assertEqual(w['jobs']['ipa']['needs'],'resolve')
  steps=w['jobs']['ipa']['steps'];runs='\n'.join(s.get('run','') for s in steps)
  self.assertIn('--expected-build 8',runs)
  self.assertIn('0.4.9 --expected-build 8',runs)
  self.assertIn('VoiceMatrix-Source-Proof.json',runs)
  self.assertIn('physicalDeviceVerified=False',runs)
  self.assertIn('likenessVerified=False',runs)
  self.assertNotIn('gh release',runs)
  self.assertEqual(runs.count('cmp frozen/Package.resolved VoiceMatrix.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'),2)
  self.assertIn('shasum -a 256 -c frozen-package.sha256',runs)
  for s in steps:
   if s.get('uses')=='actions/download-artifact@v4':self.assertNotIn('run-id',s['with'])
