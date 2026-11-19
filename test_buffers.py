import io,unittest,zipfile
from buffers import read_exact_entry

def zipdata(data=b'abc',compression=zipfile.ZIP_STORED,duplicate=False):
 b=io.BytesIO()
 with zipfile.ZipFile(b,'w',compression=compression) as z:
  z.writestr('x',data)
  if duplicate:z.writestr('x',data)
 b.seek(0);return zipfile.ZipFile(b)
class Tests(unittest.TestCase):
 def test_plain(self):
  with zipdata() as z:self.assertEqual(read_exact_entry(z,'x',3),b'abc')
 def test_wrong_size(self):
  with zipdata() as z,self.assertRaises(ValueError):read_exact_entry(z,'x',2)
 def test_compressed_refused(self):
  with zipdata(compression=zipfile.ZIP_DEFLATED) as z,self.assertRaises(ValueError):read_exact_entry(z,'x',3)
 def test_duplicate_refused(self):
  with zipdata(duplicate=True) as z,self.assertRaises(ValueError):read_exact_entry(z,'x',3)
 def test_missing(self):
  with zipdata() as z,self.assertRaises(ValueError):read_exact_entry(z,'missing',3)
