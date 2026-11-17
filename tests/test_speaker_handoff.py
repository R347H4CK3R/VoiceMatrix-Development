import pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SpeakerHandoffTests(unittest.TestCase):
 def test_exact_unique_profile_identity(self):
  p=ROOT/'VoiceMatrix/LocalSpeakerHandoff.swift'
  self.assertTrue(p.exists(),'Missing exact saved-speaker handoff policy')
  if not shutil.which('swiftc'):self.skipTest('Swift compiler unavailable')
  with tempfile.TemporaryDirectory() as d:
   exe=pathlib.Path(d)/'check'
   subprocess.run(['swiftc',str(p),str(ROOT/'tests/native/SpeakerHandoffChecks.swift'),'-o',str(exe)],check=True,timeout=60)
   subprocess.run([str(exe)],check=True,timeout=10)
 def test_controller_guards_job_activity_and_preserves_selection(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertIn('func selectSpeaker(jobID:',s)
  b=s.split('func selectSpeaker(jobID:',1)[1].split('func speakerAssetURL',1)[0]
  for x in ['!busy, active, !library.busy','!audio.processingInUse, !audio.microphoneInUse','current?.id == jobID','validatedSpeakerAssetURL(speaker, preview: false)','LocalSpeakerHandoff.voiceID','library.selectedID = voiceID']:
   self.assertIn(x,b)
  for x in ['removeItem','start(','speak(','convertRecording(','syncVoices(']:self.assertNotIn(x,b)
 def test_ui_navigates_only_after_explicit_bound_selection(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  for x in ['Browse saved voices','Make speech with this speaker','Change my voice with this speaker','jobID: job.id','mode: .speech','mode: .conversion','.navigationDestination(item: $speakerDestination)','if local.selectSpeaker(jobID: jobID','speakerDestination = mode']:
   self.assertIn(x,s)
  self.assertNotIn('Use saved references for new speech',s)
 def test_every_controller_target_compiles_handoff_policy(self):
  import yaml
  project=yaml.safe_load((ROOT/'project.yml').read_text())
  for name,target in project['targets'].items():
   paths=[s['path'] for s in target.get('sources',[]) if isinstance(s,dict)]
   if 'VoiceMatrix/LocalVideoStudio.swift' in paths:
    self.assertIn('VoiceMatrix/LocalSpeakerHandoff.swift',paths,name)
 def test_native_policy_is_mandatory_in_linux_gate(self):
  import json
  manifest=json.loads((ROOT/'tests/platform-regression-coverage.json').read_text())
  self.assertIn('test_speaker_handoff.SpeakerHandoffTests.test_exact_unique_profile_identity',manifest['posixTestIDs'])
 def test_speaker_group_does_not_override_action_identifiers(self):
  s=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  self.assertNotIn('}.accessibilityIdentifier("local-video-speaker-" + speaker)',s)
  self.assertIn('.accessibilityIdentifier("local-video-speaker-speech-" + speaker)',s)
  self.assertIn('.accessibilityIdentifier("local-video-speaker-conversion-" + speaker)',s)
