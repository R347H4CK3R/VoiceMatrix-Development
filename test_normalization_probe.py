import unittest,numpy as np
from normalization_probe import centered_normalize,source_order_normalize
class Tests(unittest.TestCase):
 def test_constant_stable_zero(self):
  for n in (3,101,1501):
   a=np.full((128,n),np.float32(np.log(2**-24)),dtype=np.float32)
   np.testing.assert_array_equal(centered_normalize(a,n),np.zeros_like(a))
 def test_invalid_tail_zero(self):
  a=np.array([[1,2,99]],dtype=np.float32);self.assertEqual(centered_normalize(a,2)[0,2],0)
 def test_analytic_pair(self):
  a=np.array([[1,3]],dtype=np.float32);np.testing.assert_allclose(centered_normalize(a,2),np.array([[-1,1]])/(2**.5+1e-5),rtol=1e-6)
 def test_undefined_rejected(self):
  with self.assertRaises(ValueError):centered_normalize(np.ones((1,2),dtype=np.float32),1)
 def test_reject_nonfinite(self):
  with self.assertRaises(ValueError):centered_normalize(np.array([[np.nan,0]],dtype=np.float32),2)
