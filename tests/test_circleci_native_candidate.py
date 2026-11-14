import importlib.util, pathlib, unittest, yaml
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
from tools import native_ui_preflight, prepare_circleci_native
class CircleNativeCandidateTests(unittest.TestCase):
 def test_inert_and_generated_from_existing_steps(self):
  config=yaml.safe_load(prepare_circleci_native.DEST.read_text())
  self.assertEqual(config,prepare_circleci_native.configuration())
  self.assertFalse(config['parameters']['run-native']['default'])
  native=yaml.safe_load((ROOT/'.circleci/config.yml').read_text())
  self.assertFalse(native['parameters']['run-native']['default'])
  self.assertEqual(native['jobs']['native-ui']['resource_class'],'m4pro.medium')
  self.assertEqual(native['parameters']['xcode-version']['default'],'26.4.1')
  self.assertEqual(native['jobs']['native-ui']['steps'],config['jobs']['native-ui']['steps'])
  commands='\n'.join(s['run']['command'] for s in config['jobs']['native-ui']['steps'] if isinstance(s,dict) and 'run' in s)
  self.assertNotIn('GITHUB_ENV',commands)
  self.assertIn("f.write('export SIMULATOR_ID='",commands)
  self.assertIn('test-without-building',commands)
  self.assertIn('CharacterWorkflowUITests',commands)
  self.assertNotIn('gh release',commands)
 def test_non_apple_host_rejected_without_subprocess(self):
  with patch.object(native_ui_preflight.platform,'system',return_value='Linux'),patch.object(native_ui_preflight.subprocess,'check_output') as run:
   with self.assertRaisesRegex(RuntimeError,'Apple Silicon'):native_ui_preflight.check()
   run.assert_not_called()
 def test_missing_runtime_rejected(self):
  with patch.object(native_ui_preflight.platform,'system',return_value='Darwin'),patch.object(native_ui_preflight.platform,'machine',return_value='arm64'),patch.object(native_ui_preflight.shutil,'which',return_value='/tool'),patch.object(native_ui_preflight.subprocess,'check_output',side_effect=['Xcode 26.0.1\nBuild version 17A400','{"runtimes":[]}']):
   with self.assertRaisesRegex(RuntimeError,'installed iOS 26'):native_ui_preflight.check()
