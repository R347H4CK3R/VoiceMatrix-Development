import pathlib,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RawOverlapPolicyTests(unittest.TestCase):
 def test_cluster_independent_policy_exists(self):
  self.assertTrue((ROOT/'VoiceMatrix/LocalOverlapPolicy.swift').is_file(),'No raw overlap evidence propagation exists')
