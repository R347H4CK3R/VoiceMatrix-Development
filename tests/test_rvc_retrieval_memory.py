"""Bounded neighbor selection and exact sparse-search behavior."""
import pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RetrievalMemoryTests(unittest.TestCase):
 def test_bounded_selection_and_exact_sparse_fallback(self):
  self.assertIsNotNone(shutil.which('swiftc'),'Swift is required')
  with tempfile.TemporaryDirectory() as folder:
   binary=pathlib.Path(folder)/'checks'
   subprocess.run(['swiftc','-O',str(ROOT/'VoiceMatrix/RVCNativeRetrieval.swift'),str(ROOT/'tests/native/RVCRetrievalMemoryChecks.swift'),'-o',str(binary)],check=True,timeout=60)
   result=subprocess.run([str(binary)],capture_output=True,text=True,check=True,timeout=30)
   self.assertIn('passed',result.stdout)
