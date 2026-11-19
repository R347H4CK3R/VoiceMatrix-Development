import unittest,numpy as np
from compare_cli import metrics
class Tests(unittest.TestCase):
 def test_exact(self):self.assertEqual(metrics(np.zeros((128,3),dtype='<f4'),np.zeros((128,3),dtype='<f4'),2)['valid_rms'],0)
 def test_valid_rms_not_diluted(self):
  a=np.zeros((128,1501),dtype='<f4');b=a.copy();b[:,0]=.01
  r=metrics(a,b,2);self.assertGreater(r['valid_rms'],r['rms']*10)
 def test_bad_mask(self):
  a=np.zeros((128,3),dtype='<f4');b=a.copy();b[:,2]=-0.
  with self.assertRaises(ValueError):metrics(a,b,2)
 def test_nan(self):
  a=np.zeros((128,3),dtype='<f4');b=a.copy();b[0,0]=np.nan
  with self.assertRaises(ValueError):metrics(a,b,2)

class FixtureCountTests(unittest.TestCase):
 def test_not_enough_base_cases(self):
  from compare_cli import validate_rows
  rows=[{'name':f'base-{i}','samples':240000,'validSamples':240000} for i in range(35)]+[{'name':f'native-synthetic-speech-{i}','samples':240000,'validSamples':240000} for i in range(3)]
  with self.assertRaises(ValueError):validate_rows(rows)
 def test_short_speech_not_counted(self):
  from compare_cli import validate_rows
  rows=[{'name':f'base-{i}','samples':240000,'validSamples':240000} for i in range(36)]+[{'name':f'native-synthetic-speech-{i}','samples':16000,'validSamples':16000} for i in range(2)]
  with self.assertRaises(ValueError):validate_rows(rows)
