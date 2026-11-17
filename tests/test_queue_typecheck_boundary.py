import pathlib, unittest, re
ROOT=pathlib.Path(__file__).resolve().parents[1]
STUB='tests/native/QueueLocalStudioDestinationStub.swift'
class QueueTypecheckBoundary(unittest.TestCase):
 def test_only_narrow_harness_uses_stub(self):
  workflow=(ROOT/'.github/workflows/native-queue.yml').read_text()
  self.assertIn('-D QUEUE_BOUNDARY_TYPECHECK '+STUB,workflow)
  stub=(ROOT/STUB).read_text()
  self.assertIn('#if QUEUE_BOUNDARY_TYPECHECK',stub)
  self.assertIn('struct LocalVideoStudioView: View',stub)
  project=(ROOT/'project.yml').read_text()
  application=project.split('  VoiceMatrix:\n',1)[1].split('  VoiceMatrixTests:',1)[0]
  sources=application.split('    sources:\n',1)[1].split('    dependencies:',1)[0]
  source_roots=[(ROOT/s).resolve() for s in re.findall(r'^    - path: (.+)$',sources,re.M)]
  self.assertTrue(source_roots)
  target=(ROOT/STUB).resolve()
  for root in source_roots:
   self.assertFalse(target==root or root in target.parents, 'Test destination must never enter app target')
  self.assertIn((ROOT/'VoiceMatrix').resolve(),source_roots)
