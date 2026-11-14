import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class NativeSynthesisTests(unittest.TestCase):
 def test_tensor_bytes_and_reject_malformed_assets_before_inference(self):
  sources=[ROOT/'VoiceMatrix/RVCSynthesisInputs.swift',ROOT/'VoiceMatrix/RVCSynthesisAssets.swift',ROOT/'tests/native/RVCSynthesisChecks.swift']
  self.assertTrue(all(p.exists() for p in sources),'Native synthesis contract is missing')
  with tempfile.TemporaryDirectory() as tmp:
   binary=str(pathlib.Path(tmp)/'synthesis')
   subprocess.run(['swiftc',*map(str,sources),'-o',binary],check=True,timeout=60)
   subprocess.run([binary],check=True,timeout=30)
