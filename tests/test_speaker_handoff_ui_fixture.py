import pathlib,subprocess,unittest,yaml
from tools.test_shell import check_bash_syntax
ROOT=pathlib.Path(__file__).resolve().parents[1]
class HandoffUIFixture(unittest.TestCase):
 def test_fixture_uses_real_store_and_refuses_existing_destination(self):
  p=ROOT/'tests/native/SpeakerHandoffUIFixture.swift';self.assertTrue(p.exists())
  s=p.read_text();self.assertIn('CharacterFolderStore(root:',s);self.assertIn('try await store.importCollection',s);self.assertIn('!fm.fileExists(atPath: output.path)',s)
  self.assertIn('Synthetic Handoff Alpha',s);self.assertIn('Synthetic Handoff Beta',s)
 def test_both_routes_and_no_generation_asserted(self):
  p=ROOT/'VoiceMatrixUITests/SpeakerHandoffUITests.swift';self.assertTrue(p.exists());s=p.read_text()
  for x in ['local-video-speaker-speech-one','local-video-speaker-conversion-two','Synthetic Handoff Alpha','Synthetic Handoff Beta','Stop after current step','create-character-speech','CONVERT'] :self.assertIn(x,s)
  self.assertNotIn('-ui-test-import',s)
 def test_own_simulator_workflow_seeds_after_install_and_checks_actual_execution(self):
  p=ROOT/'.github/workflows/speaker-handoff-ui.yml';self.assertTrue(p.exists());w=yaml.safe_load(p.read_text());self.assertEqual(w['permissions'],{'contents':'read'})
  steps=w['jobs']['ui']['steps'];runs='\n'.join(s.get('run','') for s in steps)
  for x in ['simctl install','get_app_container','CharacterFolderStore.swift','SpeakerHandoffUIFixture.swift','--verify','testExplicitSavedSpeakerSpeechAndConversionRoutes'] :self.assertIn(x,runs)
  for s in steps:
   if 'run' in s:check_bash_syntax(s['run'])

class FixturePreservation(unittest.TestCase):
 def test_seed_never_overwrites_and_verification_rejects_changes(self):
  import tempfile,sys,json
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);container=root/'CoreSimulator/Devices/test/data/Containers/Data/Application/test';container.mkdir(parents=True)
   fixture=root/'fixture/Application Support'
   for name in ['LocalVideoStudio','CharacterReferences']:(fixture/name).mkdir(parents=True)
   (fixture/'LocalVideoStudio/job.json').write_text('{}');(fixture/'LocalVideoStudio/reference.wav').write_bytes(b'synthetic')
   (fixture/'CharacterReferences/index.json').write_text('{}')
   receipt=root/'receipt.json';cmd=[sys.executable,str(ROOT/'tools/speaker_handoff_fixture.py'),str(container),str(fixture.parent),str(receipt)]
   subprocess.run(cmd,check=True,capture_output=True);subprocess.run(cmd+['--verify'],check=True,capture_output=True)
   self.assertNotEqual(subprocess.run(cmd,capture_output=True).returncode,0)
   target=container/'Library/Application Support/LocalVideoStudio/reference.wav';target.write_bytes(b'changed')
   self.assertNotEqual(subprocess.run(cmd+['--verify'],capture_output=True).returncode,0)
   self.assertEqual(target.read_bytes(),b'changed')
