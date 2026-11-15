import json,pathlib,shutil,tempfile,unittest
from tools import vendored_fluid as v
ROOT=pathlib.Path(__file__).resolve().parents[1]
class VendoredFluidTests(unittest.TestCase):
 def test_exact_inventory_and_upstream_tree(self):
  p=v.verify(ROOT); self.assertEqual(p['upstreamTree'],'2234ed3bb9af2f02d187dbd4c35e51f9eef18f44');self.assertEqual(p['fileCount'],960)
 def test_mutation_missing_extra_symlink_fail(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);shutil.copytree(ROOT/'Vendors',root/'Vendors');target=root/'Vendors/FluidAudio/LICENSE';original=target.read_bytes()
   target.write_bytes(original+b'x')
   with self.assertRaises(ValueError):v.verify(root)
   target.unlink()
   with self.assertRaises(ValueError):v.verify(root)
   target.symlink_to(ROOT/'Vendors/FluidAudio/LICENSE')
   with self.assertRaises(ValueError):v.verify(root)
   target.unlink();target.write_bytes(original)
   (target.parent/'extra.swift').write_text('bad')
   with self.assertRaises(ValueError):v.verify(root)
 def test_inventory_cannot_change_upstream_identity(self):
  m=json.loads((ROOT/'Vendors/FluidAudio.inventory.json').read_text());m['files']['LICENSE']['upstreamBlob']='0'*40
  with self.assertRaises(ValueError):v.check_manifest(m)
  m=json.loads((ROOT/'Vendors/FluidAudio.inventory.json').read_text());m['revision']='0'*40
  with self.assertRaises(ValueError):v.check_manifest(m)

 def test_remote_pin_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'Package.resolved';p.write_text(json.dumps({'pins':[{'identity':'fluidaudio'}]}))
   with self.assertRaises(ValueError):v.check_resolved(p)
   p.write_text(json.dumps({'pins':[{'identity':'speech-swift'}]}));v.check_resolved(p)

 def test_all_third_party_licenses_captured(self):
  captured=v.notices(ROOT)
  for path in (ROOT/'Vendors/FluidAudio/ThirdPartyLicenses').rglob('*'):
   if path.is_file():self.assertEqual(captured['fluid-audio-vendored/'+path.relative_to(ROOT/'Vendors/FluidAudio').as_posix()],path.read_bytes())
  self.assertIn('fluid-audio-vendored/Tests/FluidAudioTests/ASR/Parakeet/SlidingWindow/Fixtures/Vocabulary/LICENSE_CC_BY_4_0.txt',captured)
