import unittest,tempfile,pathlib,json
from generate import make_cases,write_fixture
class Tests(unittest.TestCase):
 def test_domains(self):
  items=list(make_cases());self.assertGreater(len(items),25)
  for name,a,valid in items:self.assertTrue(257<=len(a)<=240000 and 160<=valid<=len(a))
 def test_names_unique(self):
  names=[x[0] for x in make_cases()];self.assertEqual(len(names),len(set(names)))
 def test_write_one(self):
  with tempfile.TemporaryDirectory() as d:
   name,a,valid=next(make_cases());row=write_fixture(pathlib.Path(d),name,a,valid)
   self.assertEqual(row['frames'],len(a)//160+1);self.assertEqual((pathlib.Path(d)/(name+'.mel.f32le')).stat().st_size,128*row['frames']*4)

class SpeechWindowTests(unittest.TestCase):
 def test_dedup_twenty_second_windows(self):
  import wave,numpy as np
  from generate import speech_cases
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)/'speech.wav'
   with wave.open(str(p),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(16000);w.writeframes(np.zeros(320000,dtype='<i2').tobytes())
   names=[x[0] for x in speech_cases(p)];self.assertEqual(len(names),len(set(names)))

class TailTests(unittest.TestCase):
 def test_nonzero_tail_present(self):
  import numpy as np
  self.assertTrue(any(np.any(a[valid:]!=0) for name,a,valid in make_cases() if name.startswith('nonzero-tail-')))
