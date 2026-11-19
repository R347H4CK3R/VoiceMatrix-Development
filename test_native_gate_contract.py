import unittest,numpy as np
from native_gate import compare,cases
class Tests(unittest.TestCase):
 def test_exact(self):self.assertEqual(compare(np.ones(2),np.ones(2)),{'max_abs':0.,'rms':0.})
 def test_error_fails(self):
  with self.assertRaises(AssertionError):compare(np.zeros(2),np.ones(2))
 def test_nan_fails(self):
  with self.assertRaises(AssertionError):compare(np.zeros(2),np.array([np.nan,0]))
 def test_shape_fails(self):
  with self.assertRaises(AssertionError):compare(np.zeros(2),np.zeros(3))
 def test_cases_safe(self):
  items=list(cases());self.assertEqual(len(items),21)
  for name,x,n in items:
   self.assertTrue(257<=len(x)<=240000);self.assertTrue(160<=n<=len(x));self.assertEqual(x.dtype,np.float32)

class EvidenceTests(unittest.TestCase):
 def test_default_matches_full_trace(self):
  import pathlib
  s=(pathlib.Path(__file__).parent/'native_gate.py').read_text()
  self.assertIn('ct.RangeDim(1,240000,default=240000)',s)
 def test_records_current_case(self):
  import pathlib
  s=(pathlib.Path(__file__).parent/'native_gate.py').read_text()
  self.assertIn("report['current_case']=name",s)
