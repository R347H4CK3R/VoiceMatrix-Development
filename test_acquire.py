import hashlib,io,pathlib,tempfile,unittest
from acquire import verified_copy
class Response(io.BytesIO):
 status=200
 headers={}
class Tests(unittest.TestCase):
 def run_copy(self,data=b'abc',size=3,digest=None,status=200):
  t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);p=pathlib.Path(t.name)/'model'
  r=Response(data);r.status=status
  verified_copy(r,p,size,digest or hashlib.sha256(b'abc').hexdigest());return p
 def test_valid(self):self.assertEqual(self.run_copy().read_bytes(),b'abc')
 def test_short(self):
  with self.assertRaises(ValueError):self.run_copy(b'ab')
 def test_long(self):
  with self.assertRaises(ValueError):self.run_copy(b'abcd')
 def test_wrong_hash(self):
  with self.assertRaises(ValueError):self.run_copy(b'abd')
 def test_partial_status(self):
  with self.assertRaises(ValueError):self.run_copy(status=206)
 def test_no_clobber(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t)/'x';p.write_bytes(b'original')
   with self.assertRaises(FileExistsError):verified_copy(Response(b'abc'),p,3,hashlib.sha256(b'abc').hexdigest())
   self.assertEqual(p.read_bytes(),b'original')
