import ast,pathlib,tempfile,unittest
from native_reference import selected_source,verified_buffers
class Tests(unittest.TestCase):
 def test_exact_methods(self):
  names={n.name for n in ast.parse(selected_source()).body};self.assertEqual(names,{'normalize_batch','splice_frames','FilterbankFeatures'})
 def test_hash_fail(self):
  with tempfile.NamedTemporaryFile() as f:
   f.write(b'print("not trusted")');f.flush()
   with self.assertRaises(ValueError):selected_source(pathlib.Path(f.name))
 def test_original_shapes(self):
  w,fb=verified_buffers();self.assertEqual(w.shape,(400,));self.assertEqual(fb.shape,(1,128,257))
 def test_no_unpickle_import(self):
  self.assertNotIn('pickle',selected_source())
