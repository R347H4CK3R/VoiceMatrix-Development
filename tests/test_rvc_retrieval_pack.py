import pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RetrievalPackAdmission(unittest.TestCase):
 def test_profile_manifest_cannot_override_file_identity(self):
  with tempfile.TemporaryDirectory() as folder:
   root=pathlib.Path(folder);pack=root/'pack';pack.mkdir();exe=root/'check'
   names=['RVCSynthesisInputs','RVCSynthesisAssets','RVCDiskVectorBank','RVCNativeRetrieval','RVCRetrievalAssets']
   subprocess.run(['swiftc','-O',*[str(ROOT/'VoiceMatrix'/(n+'.swift')) for n in names],str(ROOT/'tests/native/RVCRetrievalDescriptorChecks.swift'),'-o',str(exe)],check=True,timeout=60)
   subprocess.run([str(exe),str(pack)],check=True,timeout=30)
