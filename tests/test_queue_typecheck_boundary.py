import pathlib, unittest, yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
STUB='tests/native/QueueLocalStudioDestinationStub.swift'
class QueueTypecheckBoundary(unittest.TestCase):
 def test_only_narrow_harness_uses_stub(self):
  workflow=(ROOT/'.github/workflows/native-queue.yml').read_text()
  self.assertIn('-D QUEUE_BOUNDARY_TYPECHECK '+STUB,workflow)
  stub=(ROOT/STUB).read_text()
  self.assertIn('#if QUEUE_BOUNDARY_TYPECHECK',stub)
  self.assertIn('struct LocalVideoStudioView: View',stub)
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  source_roots=[(ROOT/s['path']).resolve() for s in project['targets']['VoiceMatrix']['sources']]
  target=(ROOT/STUB).resolve()
  for root in source_roots:
   self.assertFalse(target==root or root in target.parents, 'Test destination must never enter app target')
  self.assertIn((ROOT/'VoiceMatrix').resolve(),source_roots)
