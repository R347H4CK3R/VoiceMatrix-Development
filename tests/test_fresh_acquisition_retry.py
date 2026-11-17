import json,pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class FreshAcquisitionRetryTests(unittest.TestCase):
 def test_retry_policy_rechecks_original_source_not_cached_media(self):
  source=(ROOT/'VoiceMatrix/LocalMediaURLPolicy.swift').read_text()
  self.assertIn('static func freshAcquisitionInput',source)
  if not shutil.which('swiftc'):self.skipTest('Swift compiler unavailable')
  with tempfile.TemporaryDirectory() as d:
   binary=pathlib.Path(d)/'checks'
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/LocalMediaURLPolicy.swift'),str(ROOT/'tests/native/FreshAcquisitionRetryChecks.swift'),'-o',str(binary)],check=True,timeout=60)
   subprocess.run([str(binary)],check=True,timeout=10)
 def test_controller_requires_current_job_confirmation_and_uses_new_job(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertIn('func retryAcquisition(jobID: UUID, authorized: Bool',s)
  body=s.split('func retryAcquisition(jobID:',1)[1].split('func resume(',1)[0]
  for token in ('guard authorized, !busy, active','current?.id == jobID','freshAcquisitionURL','start(source, authorized: true'):
   self.assertIn(token,body)
  for forbidden in ('removeItem','LocalMediaAcquisition.acquire','acquisition.json','operation ='):
   self.assertNotIn(forbidden,body)
 def test_ui_requires_explicit_confirmation_bound_to_job(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  for token in ('local-video-fresh-download','retryRequest = FreshDownloadRequest(id: job.id)', '.alert(item: $retryRequest)', 'local.retryAcquisition(jobID: request.id, authorized: true', 'secondaryButton: .cancel()', 'Previous jobs and files are kept', 'may still fail'):
   self.assertIn(token,s)

 def test_native_retry_policy_cannot_be_skipped_in_linux_gate(self):
  coverage=json.loads((ROOT/'tests/platform-regression-coverage.json').read_text())
  self.assertIn('test_fresh_acquisition_retry.FreshAcquisitionRetryTests.test_retry_policy_rechecks_original_source_not_cached_media',coverage['posixTestIDs'])
