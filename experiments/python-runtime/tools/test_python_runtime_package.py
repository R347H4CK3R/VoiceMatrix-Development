import importlib.util, os, pathlib, tempfile, unittest
P=pathlib.Path(__file__).with_name('prepare_python_runtime.py')
class PackagingTests(unittest.TestCase):
 def test_runtime_preparer_exists(self): self.assertTrue(P.exists(), 'Missing pinned runtime preparer')
 def test_rejects_modified_archive_before_extraction(self):
  if not P.exists(): self.fail('Missing verifier')
  spec=importlib.util.spec_from_file_location('runtime',P); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'archive';p.write_bytes(b'not the pinned archive')
   with self.assertRaises(ValueError): m.verify(p)
 def test_actual_download_matches_pin(self):
  if not P.exists(): self.fail('Missing verifier')
  spec=importlib.util.spec_from_file_location('runtime',P); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
  archive=pathlib.Path(os.environ.get('VM_PYTHON_ARCHIVE',str(pathlib.Path(__file__).resolve().parents[1]/'Vendors/Python/Python-3.13-iOS-support.b18.tar.gz')))
  self.assertTrue(archive.is_file(), 'Required downloaded SDK verification fixture missing')
  m.verify(archive)
if __name__=='__main__': unittest.main()
