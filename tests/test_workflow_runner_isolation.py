from tools.test_shell import check_bash_syntax
import pathlib,unittest,yaml,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[1]
class IsolationTests(unittest.TestCase):
 def test_exact_methods_and_owned_reboot_preserve_gates(self):
  d=yaml.safe_load((ROOT/'.github/workflows/character-ui-smoke.yml').read_text())
  steps=d['jobs']['ui']['steps']
  for step in steps:
   if 'run' in step:check_bash_syntax(step['run'])
  imports=next(s for s in steps if s.get('name','').startswith('Import a synthetic'))
  names=next(s for s in steps if s.get('name','').startswith('Assign a voice'))
  for s,method,result in [(imports,'testImportSelectListenAndKeepVoicesAfterRelaunch','character-workflow'),(names,'testUserAssignedNamePersistsAndCanBeReset','character-naming')]:
   self.assertIn('-only-testing:VoiceMatrixUITests/CharacterWorkflowUITests/'+method,s['run'])
   self.assertIn('-resultBundlePath '+result+'.xcresult',s['run'])
   self.assertIn('exit 1',s['run'])
   self.assertNotIn('continue-on-error',s)
  boot=steps[steps.index(names)-1]['run']
  self.assertIn("device=os.environ['SIMULATOR_ID']",boot)
  for command in ["'shutdown',device","'boot',device","'bootstatus',device"]:self.assertIn(command,boot)
  for forbidden in ["'erase'","'uninstall'","'delete'"]:self.assertNotIn(forbidden,boot)
  self.assertIn('timeout=360',boot)
  source=(ROOT/'VoiceMatrixUITests/CharacterWorkflowUITests.swift').read_text()
  self.assertGreaterEqual(source.count('app.terminate()'),2)
  self.assertGreaterEqual(source.count('app.launch()'),4)
  artifact=next(s for s in steps if s.get('uses')=='actions/upload-artifact@v4')
  for name in ['character-workflow.log','character-naming.log','character-naming.xcresult','naming-screenshots']:self.assertIn(name,artifact['with']['path'])
