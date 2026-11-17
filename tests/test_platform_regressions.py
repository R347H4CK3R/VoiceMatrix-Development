import io,json,pathlib,unittest
from tools import run_platform_regressions as p
class Probe(unittest.TestCase):
 def runTest(self):pass
 def id(self):return getattr(self,"identity",super().id())

def case(name):
 t=Probe();t.identity=name;return t
class PlatformRegressionTests(unittest.TestCase):
 def suite(self):return unittest.TestSuite([case('native'),case('worker')])
 def test_windows_only_filters_exact_native_identity(self):
  self.assertEqual([x.id() for x in p.flatten(p.select(self.suite(),'windows-worker',['native']))],['worker'])
  self.assertEqual([x.id() for x in p.flatten(p.select(self.suite(),'full',['native']))],['native','worker'])
 def test_missing_renamed_or_duplicate_identity_fails_closed(self):
  for delegated in [[],['missing'],['native','renamed']]:
   with self.assertRaises(ValueError):p.select(self.suite(),'windows-worker',delegated)
  with self.assertRaises(ValueError):p.select(unittest.TestSuite([case('native'),case('native')]),'full',['native'])
 def test_native_success_required_not_skip_or_failure(self):
  runner=unittest.TextTestRunner(stream=io.StringIO(),resultclass=p.EvidenceResult)
  result=runner.run(self.suite());self.assertTrue(p.native_coverage_passed(result,['native']))
  result.passed.remove('native');self.assertFalse(p.native_coverage_passed(result,['native']))
  result.passed.add('native');result.errors.append((case('worker'),'failure'))
  self.assertFalse(p.native_coverage_passed(result,['native']))
 def test_exact_manifest_and_workflow_bind_both_platforms(self):
  manifest=json.loads(p.MANIFEST.read_text(encoding='utf-8'))['posixTestIDs']
  self.assertEqual(len(manifest),54);self.assertEqual(len(manifest),len(set(manifest)))
  discovered=unittest.defaultTestLoader.discover(str(p.ROOT/'tests'))
  ids={t.id() for t in p.flatten(discovered)};self.assertTrue(set(manifest)<=ids)
  workflow=(p.ROOT/'.github/workflows/queue-processor.yml').read_text()
  self.assertIn('os: [ubuntu-latest, windows-latest]',workflow)
  self.assertIn("runner.os == 'Windows' && 'windows-worker' || 'full'",workflow)
  self.assertIn('fail-fast: false',workflow)
  self.assertLess(workflow.index('core.autocrlf false'),workflow.index('actions/checkout@v4'))
  self.assertIn("PYTHONUTF8: '1'",workflow)
  self.assertIn('Git\\bin',workflow)
