import unittest
import numpy as np
from tools import speaker_candidates as sc
class Model:
 def __init__(self,vectors):self.vectors=iter(vectors)
 def embed(self,a):return np.array(next(self.vectors),dtype=np.float32)
class RegionJoinTests(unittest.TestCase):
 def test_supported_nearby_turns_can_share_a_window(self):
  regions=[(0,64000),(72000,136000)]
  self.assertEqual(sc._join_supported_regions(np.zeros(160000,dtype=np.float32),regions,Model([[1,0],[1,0]]),lambda:False),[(0,136000)])
 def test_different_speakers_remain_separate(self):
  regions=[(0,64000),(72000,136000)]
  self.assertEqual(sc._join_supported_regions(np.zeros(160000,dtype=np.float32),regions,Model([[1,0],[0,1]]),lambda:False),regions)
 def test_short_intervening_region_is_never_bridged(self):
  regions=[(0,64000),(66000,74000),(76000,140000)]
  self.assertEqual(sc._join_supported_regions(np.zeros(160000,dtype=np.float32),regions,Model([]),lambda:False),regions)
 def test_long_silence_is_never_bridged(self):
  regions=[(0,64000),(80000,144000)]
  self.assertEqual(sc._join_supported_regions(np.zeros(160000,dtype=np.float32),regions,Model([]),lambda:False),regions)
 def test_pairing_does_not_chain_through_a_third_region(self):
  regions=[(0,48000),(52800,100800),(105600,153600)]
  self.assertEqual(sc._join_supported_regions(np.zeros(160000,dtype=np.float32),regions,Model([[1,0],[1,0]]),lambda:False),[(0,100800),(105600,153600)])
 def test_cancellation_between_embeddings_stops_pairing(self):
  state=[False]
  class CancelModel:
   def embed(self,a):state[0]=True;return np.array([1,0],dtype=np.float32)
  with self.assertRaises(InterruptedError):
   sc._join_supported_regions(np.zeros(160000,dtype=np.float32),[(0,64000),(72000,136000)],CancelModel(),lambda:state[0])
