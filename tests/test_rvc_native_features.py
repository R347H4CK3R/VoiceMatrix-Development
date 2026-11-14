"""Native RVC non-neural stages: real Swift against independent NumPy equations."""
import json, pathlib, shutil, subprocess, tempfile, unittest
import numpy as np
ROOT = pathlib.Path(__file__).resolve().parents[1]

class RVCFeatureTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp = tempfile.TemporaryDirectory()
  cls.binary = pathlib.Path(cls.tmp.name)/'features'
  source=ROOT/'VoiceMatrix/RVCFeaturePreparation.swift'
  if not source.exists(): raise AssertionError('Native RVC pitch/feature preparation is missing')
  if not shutil.which('swiftc'): raise RuntimeError('Swift required; no skipped parity claims')
  subprocess.run(['swiftc',str(source),str(ROOT/'tests/native/RVCFeatureChecks.swift'),'-o',str(cls.binary)],check=True,timeout=60)
 @classmethod
 def tearDownClass(cls): cls.tmp.cleanup()
 def run_case(self,case):
  p=subprocess.run([str(self.binary)],input=json.dumps(case),text=True,capture_output=True,check=True,timeout=20)
  return json.loads(p.stdout)
 def test_pitch_interpolation_shift_and_bins(self):
  # Literal interpolation expectations catch missing edge fill and unvoiced handling.
  for pitch,shift,want in [([0,100,0,200,0],0,[100,100,150,200,200]),([0,100,0,200,0],12,[200,200,300,400,400]),([0,0],0,[0,0]),([50,1100],0,[50,1100])]:
   result=self.run_case(dict(pitch=pitch,semitones=shift))
   self.assertEqual(result['hz'],want)
   mel=1127*np.log1p(np.asarray(want)/700)
   lo=1127*np.log1p(50/700);hi=1127*np.log1p(1100/700)
   expected=np.rint(np.clip(np.where(mel>0,(mel-lo)*254/(hi-lo)+1,mel),1,255)).astype(int)
   self.assertEqual(result['coarse'],expected.tolist())
 def test_feature_retrieval_upsampling_and_protection(self):
  rng=np.random.default_rng(347)
  for rows,rate,protect in [(1,0,.33),(3,.75,.33),(149,1,.5)]:
   features=rng.normal(size=(rows,768)).astype('float32')
   vectors=rng.normal(size=(rows,8,768)).astype('float32')
   scores=rng.uniform(.1,20,size=(rows,8)).astype('float32')
   pitch=np.tile([0,100],rows).astype('float32')
   weights=(1/scores)**2;weights/=weights.sum(axis=1,keepdims=True)
   mixed=(vectors*weights[:,:,None]).sum(axis=1)*rate+(1-rate)*features
   expected=np.repeat(mixed,2,axis=0)
   if protect<.5:
    mask=np.where(pitch<1,protect,1).astype('float32')[:,None]
    expected=expected*mask+np.repeat(features,2,axis=0)*(1-mask)
   result=self.run_case(dict(features=features.ravel().tolist(),vectors=vectors.ravel().tolist(),distances=scores.ravel().tolist(),rows=rows,indexRate=rate,protect=protect,pitchHz=pitch.tolist()))
   np.testing.assert_allclose(result['features'],expected.ravel(),rtol=3e-5,atol=2e-6)
   self.assertEqual(result['frames'],rows*2)
 def test_equal_neighbor_weights_have_hand_calculated_result(self):
  vectors=[float(n) for n in range(8) for _ in range(768)]
  result=self.run_case(dict(features=[2.0]*768,vectors=vectors,distances=[1.0]*8,rows=1,indexRate=.75,protect=.33,pitchHz=[0.5,1.0]))
  np.testing.assert_allclose(result['features'][:768],2.37125,rtol=0,atol=1e-6)
  np.testing.assert_allclose(result['features'][768:],3.125,rtol=0,atol=1e-6)
 def test_disabled_retrieval_needs_no_index_and_preserves_frames(self):
  result=self.run_case(dict(features=[3.0]*768,vectors=[],distances=[],rows=1,indexRate=0,protect=.33,pitchHz=[0,100]))
  self.assertEqual(result.get('features'),[3.0]*1536)
  self.assertEqual(result.get('frames'),2)
 def test_invalid_shapes_bounds_and_degenerate_neighbors_fail(self):
  valid=dict(features=[1.0]*768,vectors=[2.0]*(8*768),distances=[1.0]*8,rows=1,indexRate=.75,protect=.33,pitchHz=[100,100])
  for field,value in [('rows',0),('rows',1501),('features',[1]),('vectors',[1]),('distances',[0]*8),('distances',[1e-30]*8),('indexRate',1.1),('protect',-.1),('pitchHz',[100])]:
   bad={**valid,field:value}; self.assertIn('error',self.run_case(bad),field)
  for pitch,shift in [([],0),([-1],0),([100],25),([100]*3001,0)]:
   self.assertIn('error',self.run_case(dict(pitch=pitch,semitones=shift)))
 def test_cancellation_before_allocation(self):
  result=self.run_case(dict(cancel=True))
  self.assertEqual(result,{'cancelled':True})
