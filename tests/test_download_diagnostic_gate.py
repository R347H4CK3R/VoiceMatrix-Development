"""Gate must require the exact diagnostic tests, not an aggregate count alone."""
from pathlib import Path
import subprocess,sys,tempfile,unittest
R=Path(__file__).resolve().parents[1]
NAMES=['LocalMediaAcquisitionTests.testMKVReceiptVerificationBindsSourceAndRejectsCorruptionAndLegacyAbsence','LocalMediaAcquisitionTests.testYouTubeAcquisitionUsesResolverPlanWithoutPagePreflight','LocalMediaAcquisitionTests.testResolverFirstAcquisitionPreservesAccessFailureAndRejectsForeignPlan','OnDeviceMediaResolverTests.testResolverDiagnosticsUseFixedAllowlistedMappings','LocalMediaAcquisitionTests.testHTMLMediaResponseRejectedWithSanitizedDiagnosticAndRetention','LocalMediaAcquisitionTests.testNonMediaTypeIsDistinctAndHTMLPageAdmissionIsUnchanged']
class DiagnosticGate(unittest.TestCase):
 def run_log(self,text):
  with tempfile.TemporaryDirectory() as d:
   p=Path(d)/'log';p.write_text(text)
   return subprocess.run([sys.executable,str(R/'tools/python-runtime/require_adapter_tests.py'),str(p)],capture_output=True).returncode
 def test_old_six_tests_cannot_satisfy_new_diagnostic_gate(self):
  text='\n'.join(f'Test Case OnDeviceMediaResolverTests.old{i} passed' for i in range(6))+'\n** TEST SUCCEEDED **'
  self.assertNotEqual(self.run_log(text),0)
 def test_exact_new_tests_are_required_and_failures_rejected(self):
  base='\n'.join(f'Test Case OnDeviceMediaResolverTests.old{i} passed' for i in range(6))+'\n** TEST SUCCEEDED **\n'
  lines=[f"Test Case '-[VoiceMatrixTests.{n.replace('.', ' ')}]' passed" for n in NAMES]
  self.assertEqual(self.run_log(base+'\n'.join(lines)),0)
  for line in lines:self.assertNotEqual(self.run_log(base+'\n'.join(x for x in lines if x!=line)),0)
  self.assertNotEqual(self.run_log(base+'\n'.join(lines)+'\nTest Case failedTest failed'),0)
 def test_workflow_executes_real_acquisition_tests(self):
  self.assertIn('-only-testing:VoiceMatrixTests/LocalMediaAcquisitionTests',(R/'.github/workflows/ondevice-resolver-app.yml').read_text())
