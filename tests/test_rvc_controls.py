import json,pathlib,subprocess,tempfile,unittest,math
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Controls(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.tmp=tempfile.TemporaryDirectory();cls.binary=str(pathlib.Path(cls.tmp.name)/'controls')
  names=['RVCNativeRetrieval','RVCNativePitch','RVCFeaturePreparation','RVCSynthesisInputs','RVCNativePreparation']
  subprocess.run(['swiftc','-O',*[str(ROOT/'VoiceMatrix'/f'{n}.swift') for n in names],str(ROOT/'tests/native/RVCControlChecks.swift'),'-o',cls.binary],check=True,timeout=90)
 @classmethod
 def tearDownClass(cls):cls.tmp.cleanup()
 def run_case(self,**x):
  p=subprocess.run([self.binary],input=json.dumps(x),text=True,capture_output=True,check=True,timeout=30);return json.loads(p.stdout)
 def test_no_retrieval_preserves_features_and_allows_missing_index(self):
  for missing in [0,1]:
   r=self.run_case(rate=0,noIndex=missing)
   self.assertEqual(r,dict(first=.25,last=.25,pitch=100,count=708096))
 def test_selected_strength_and_shift_reach_synthesizer(self):
  weights=[1/(768*(i-.25)**2)**2 for i in range(1,9)]
  neighbor=sum(i*w for i,w in zip(range(1,9),weights))/sum(weights)
  for rate in [.375,.75,1]:
   r=self.run_case(rate=rate,shift=12)
   self.assertAlmostEqual(r['first'],neighbor*rate+.25*(1-rate),places=6)
   self.assertEqual(r['pitch'],200)
 def test_default_strength_is_unchanged(self):
  self.assertEqual(self.run_case(),self.run_case(rate=.75,shift=0))
 def test_invalid_controls_and_missing_required_index_fail(self):
  for case in [dict(rate=-.1),dict(rate=1.1),dict(shift=25),dict(shift=-25),dict(noIndex=1,rate=.375)]:
   self.assertEqual(self.run_case(**case),{'rejected':True})
