import io,tarfile,unittest
from archive_config import read_config

def archive(name='model_config.yaml', payload=b'preprocessor: {}\n',kind=tarfile.REGTYPE):
 b=io.BytesIO()
 with tarfile.open(fileobj=b,mode='w:gz') as t:
  x=tarfile.TarInfo(name);x.size=len(payload);x.type=kind;t.addfile(x,io.BytesIO(payload) if kind==tarfile.REGTYPE else None)
 b.seek(0);return b

class ArchiveTests(unittest.TestCase):
 def test_plain_config(self):self.assertEqual(read_config(archive()),b'preprocessor: {}\n')
 def test_dot_prefix(self):self.assertEqual(read_config(archive('./model_config.yaml')),b'preprocessor: {}\n')
 def test_traversal(self):
  with self.assertRaises(ValueError):read_config(archive('../model_config.yaml'))
 def test_symlink(self):
  with self.assertRaises(ValueError):read_config(archive(kind=tarfile.SYMTYPE))
 def test_limit(self):
  with self.assertRaises(ValueError):read_config(archive(payload=b'a'*20),max_config=10)
 def test_missing(self):
  with self.assertRaises(ValueError):read_config(archive('elsewhere.yaml'))
 def test_stream_budget(self):
  with self.assertRaises(ValueError):read_config(archive('weights',b'a'*10000),max_scan=2048)

class HostileHeaders(unittest.TestCase):
 def test_gzip_name_raw_budget(self):
  b=io.BytesIO(b'\x1f\x8b\x08\x08'+b'\0'*6+b'a'*1000+b'\0')
  with self.assertRaises(ValueError):read_config(b,max_raw=64)
 def test_sparse_config(self):
  with self.assertRaises(ValueError):read_config(archive(kind=tarfile.GNUTYPE_SPARSE))
