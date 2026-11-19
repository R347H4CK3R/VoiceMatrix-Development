import unittest,numpy as np
try:
 from oracle import features
except ImportError:
 def features(*a,**kw):return None
class OracleTests(unittest.TestCase):
 def test_old_length_includes_center_frame(self):
  r=features(np.ones(8),8,np.ones((1,3)),np.ones(4),2,normalize=False)
  self.assertIsNotNone(r);self.assertEqual(r[1],5)
 def test_reflection_not_zero_padding(self):
  r=features(np.array([1.,2.,3.,4.]),4,np.array([[1.,0.,0.]]),np.ones(4),2,preemph=None,normalize=False)
  self.assertIsNotNone(r);np.testing.assert_allclose(r[0][0],np.log(np.array([64.,100.,144.])+2**-24))
 def test_preemphasis_keeps_samples_past_valid_before_stft(self):
  r=features(np.array([1.,2.,3.,4.]),2,np.array([[1.,0.,0.]]),np.ones(4),2,preemph=.5,normalize=False)
  self.assertIsNotNone(r);self.assertAlmostEqual(r[0][0,1],np.log(49+2**-24));self.assertEqual(r[0][0,2],0)
 def test_silence_finite_normalization(self):
  r=features(np.zeros(8),8,np.ones((2,3)),np.ones(4),2)
  self.assertIsNotNone(r);np.testing.assert_array_equal(r[0],np.zeros((2,5)))
 def test_reject_one_valid_frame_normalization(self):
  with self.assertRaises(ValueError):features(np.zeros(8),0,np.ones((2,3)),np.ones(4),2)
