import importlib.util,pathlib,unittest,io,tempfile,hashlib
P=pathlib.Path(__file__).parent
spec=importlib.util.spec_from_file_location('stage_original_asr',P/'stage_models.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
class Tests(unittest.TestCase):
 def test_exact_budget(self):
  lock=m.load_lock();self.assertEqual(sum(x['size'] for x in lock['files'].values() if 'sourcePath'in x),631653214)
 def test_no_forbidden_model(self):
  names=m.load_lock()['files'];self.assertEqual(len(names),19);self.assertFalse(any('Preprocessor' in x or 'Encoder8s' in x or 'CTC' in x for x in names))
 def test_local_original_buffers(self):
  lock=m.load_lock()
  for n in ['Frontend/window.f32le','Frontend/filterbank.f32le']:
   self.assertEqual(hashlib.sha256((P/n).read_bytes()).hexdigest(),lock['files'][n]['sha256'])
 def test_bad_lock_refused(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t)/'lock';p.write_bytes(b'{}')
   with self.assertRaises(ValueError):m.load_lock(p)
 def test_app_binds_exact_replacement(self):
  s=(P.parents[1]/'VoiceMatrix/BundledASRAssets.swift').read_text()
  lock=m.load_lock()
  for token in [m.LOCK_SHA,lock['repository'],lock['revision'],'lock.files.count == 19']: self.assertIn(token,s)
 def test_corrupt_and_oversize_refused(self):
  with tempfile.TemporaryDirectory() as t:
   for index,b in enumerate([b'abcd',b'ab',b'bad']):
    with self.assertRaises(ValueError):m.copy_verified(io.BytesIO(b),pathlib.Path(t)/str(index),{'size':3,'sha256':hashlib.sha256(b'abc').hexdigest()})
 def test_exclusive_output(self):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t)/'x';p.write_bytes(b'keep')
   with self.assertRaises(FileExistsError):m.copy_verified(io.BytesIO(b'abc'),p,{'size':3,'sha256':hashlib.sha256(b'abc').hexdigest()})
   self.assertEqual(p.read_bytes(),b'keep')
