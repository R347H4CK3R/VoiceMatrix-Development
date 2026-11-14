import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CandidateAdmission(unittest.TestCase):
 def test_exact_model_identity_and_retrieval_pairing(self):
  with tempfile.TemporaryDirectory() as d:
   exe=str(pathlib.Path(d)/'admission')
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/RVCSynthesisInputs.swift'),str(ROOT/'VoiceMatrix/RVCSynthesisAssets.swift'),str(ROOT/'tests/native/RVCModelAdmissionChecks.swift'),'-o',exe],check=True,timeout=60)
   subprocess.run([exe],check=True,timeout=30)
