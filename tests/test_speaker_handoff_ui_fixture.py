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

 def test_actual_test_without_building_summary_and_fail_closed_oracle(self):
  from unittest.mock import patch
  workflow=yaml.safe_load((ROOT/'.github/workflows/speaker-handoff-ui.yml').read_text())
  step=next(s['run'] for s in workflow['jobs']['ui']['steps'] if s.get('name')=='Tap both real handoff buttons and verify preserved data')
  checker=step.split("python3 - <<'PY'\n",1)[1].split('\nPY',1)[0]
  passed="Test Case '-[VoiceMatrixUITests.SpeakerHandoffUITests testExplicitSavedSpeakerSpeechAndConversionRoutes]' passed (91.549 seconds).\n"
  summary='** TEST EXECUTE SUCCEEDED **\n'
  with patch('pathlib.Path.read_text',return_value=passed+summary):exec(checker,{})
  for invalid in [summary,passed,passed+'** TEST EXECUTE FAILED **',passed.replace(' passed',' skipped')+summary,passed+summary+"Test Case 'other' failed",passed+summary+"Test Case 'other' skipped"]:
   with self.subTest(log=invalid),patch('pathlib.Path.read_text',return_value=invalid),self.assertRaises(AssertionError):exec(checker,{})
  self.assertLess(step.index('assert '),step.index('--verify'))

class FixturePreservation(unittest.TestCase):
 def test_seed_never_overwrites_and_verification_rejects_changes(self):
  import tempfile,sys,json,uuid,importlib.util
  from unittest.mock import patch
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);sid=str(uuid.uuid4());container=root/'CoreSimulator/Devices'/sid/'data/Containers/Data/Application'/str(uuid.uuid4());container.mkdir(parents=True)
   fixture=root/'fixture/Application Support'
   for name in ['LocalVideoStudio','CharacterReferences']:(fixture/name).mkdir(parents=True)
   (fixture/'LocalVideoStudio/job.json').write_text('{}');(fixture/'LocalVideoStudio/reference.wav').write_bytes(b'synthetic')
   (fixture/'CharacterReferences/index.json').write_text('{}')
   receipt=root/'receipt.json'
   spec=importlib.util.spec_from_file_location('seed_fixture',ROOT/'tools/speaker_handoff_fixture.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
   def invoke(verify=False):
    args=['fixture',str(container),str(fixture.parent),str(receipt),'--simulator-id',sid]+(['--verify'] if verify else [])
    with patch.object(sys,'argv',args),patch.object(module.subprocess,'check_output',return_value=str(container)+'\n'):module.main()
   invoke();invoke(True)
   with self.assertRaises(AssertionError):invoke()
   target=container/'Library/Application Support/LocalVideoStudio/reference.wav';target.write_bytes(b'changed')
   with self.assertRaises(AssertionError):invoke(True)
   self.assertEqual(target.read_bytes(),b'changed')
