import pathlib,unittest,importlib.util,tempfile,shutil
R=pathlib.Path(__file__).resolve().parents[1]
class ONNXRecovery(unittest.TestCase):
 def test_official_same_version_source_and_binary_are_verified(self):
  self.assertTrue((R/'tools/vendored_onnx.py').exists(),'Missing exact official archive verifier')
  from tools.vendored_onnx import verify
  p=verify(R)
  self.assertEqual(p['version'],'1.24.2')
  self.assertEqual(p['binarySHA256'],'f7100a992d2a8135168c8afd831e6a58b465349101982aa58b3e11d36e600b54')
 def test_changed_wrapper_is_rejected(self):
  self.assertTrue((R/'Vendors/ONNXRuntime').is_dir(),'Missing same-version wrapper package')
  from tools.vendored_onnx import verify
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);shutil.copytree(R/'Vendors/ONNXRuntime',root/'Vendors/ONNXRuntime');shutil.copy(R/'Vendors/ONNXRuntime.inventory.json',root/'Vendors/ONNXRuntime.inventory.json')
   p=root/'Vendors/ONNXRuntime/objectivec/ort_env.mm';p.write_text(p.read_text()+'\n// changed')
   with self.assertRaises(ValueError):verify(root)
 def test_build_uses_verified_local_package_without_changing_runtime(self):
  self.assertIn('path: Vendors/ONNXRuntime',(R/'project.yml').read_text())
  self.assertIn('vendored_onnx',(R/'tools/character_evidence.py').read_text())

 def test_missing_extra_and_symlinked_sources_are_rejected(self):
  from tools.vendored_onnx import verify
  for mode in ('missing','extra','symlink','inventory'):
   with tempfile.TemporaryDirectory() as d:
    root=pathlib.Path(d);shutil.copytree(R/'Vendors/ONNXRuntime',root/'Vendors/ONNXRuntime');shutil.copy(R/'Vendors/ONNXRuntime.inventory.json',root/'Vendors/ONNXRuntime.inventory.json')
    p=root/'Vendors/ONNXRuntime/LICENSE'
    if mode=='missing':p.unlink()
    if mode=='extra':(p.parent/'unknown').write_text('unreviewed')
    if mode=='symlink':p.unlink();p.symlink_to(R/'Vendors/ONNXRuntime/LICENSE')
    if mode=='inventory':(root/'Vendors/ONNXRuntime.inventory.json').write_text('{}')
    with self.assertRaises(ValueError):verify(root)
