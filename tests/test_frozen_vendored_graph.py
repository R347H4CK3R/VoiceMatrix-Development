import hashlib,json,pathlib,unittest
from tools.frozen_vendored_graph import derive,SOURCE_SHA256,OBSOLETE
ROOT=pathlib.Path(__file__).resolve().parents[1]
class FrozenGraphTests(unittest.TestCase):
 def test_only_obsolete_pin_removed(self):
  raw=(ROOT/'tests/fixtures/build17-original-Package.resolved').read_bytes();before=json.loads(raw);after=json.loads(derive(raw))
  self.assertEqual(hashlib.sha256(raw).hexdigest(),SOURCE_SHA256)
  self.assertEqual(after['pins'],[p for p in before['pins'] if p!=OBSOLETE])
  self.assertEqual(len(after['pins']),40)
  self.assertEqual({k:v for k,v in before.items() if k!='pins'},{k:v for k,v in after.items() if k!='pins'})
 def test_modified_historical_graph_rejected(self):
  raw=(ROOT/'tests/fixtures/build17-original-Package.resolved').read_bytes()
  with self.assertRaises(ValueError):derive(raw+b' ')
 def test_current_frozen_consumers_migrate_before_use(self):
  for name in ['iphone-build17','reference-context-full-route','catalog-speech-quality']:
   source=(ROOT/'.github/workflows'/(name+'.yml')).read_text()
   self.assertIn('python3 -m tools.frozen_vendored_graph frozen/Package.resolved',source)
