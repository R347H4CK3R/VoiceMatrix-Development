import json,pathlib,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ReferenceAttemptTests(unittest.TestCase):
 def test_native_candidate_evidence_and_asset_binding(self):
  with tempfile.TemporaryDirectory() as temporary:
   root=pathlib.Path(temporary);binary=root/'checks'
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/LocalReferenceAttempt.swift'),str(ROOT/'tests/native/LocalReferenceAttemptChecks.swift'),'-o',str(binary)],check=True,timeout=60)
   subprocess.run([str(binary),str(root)],check=True,timeout=30)
   records=[json.loads(p.read_text()) for p in root.glob('candidate-*.json')]
   self.assertEqual(len(records),4)
   self.assertEqual({r['events'][-1]['outcome'] for r in records},{'referenceNoSpeech','saved','selected','generationRejected'})
   for record in records:
    self.assertEqual(record['schemaVersion'],1);self.assertEqual(record['sourceSHA256'],'a'*64)
    self.assertGreaterEqual(record['end']-record['start'],3)
    self.assertLessEqual(len(record['events']),16)
