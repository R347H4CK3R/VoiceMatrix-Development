import pathlib,subprocess,tempfile,shutil,unittest,yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
class IntegrationTests(unittest.TestCase):
 def test_actual_path_and_no_injected_results(self):
  s=(ROOT/'probes/catalog-quality-integration/Diagnostic.swift').read_text()
  for text in ['library.speak(text,audio:audio,studio:speech)','library.cancel();try await settle()','rejection.wordErrorRate==0.125','library.output==good','library.deleteSpeechHistory(canceledID)','reload.output==nil','uiPlaybackExportVerified":false','name+"-request.json"','finalStore.referenceURL(id:profile.id)','digest(file)==references[profile.id]']:
   self.assertIn(text,s)
  self.assertNotIn('library.output =',s)
  self.assertNotIn('engine.speak(',s)
  self.assertNotIn('quality.check(',s)
 def test_workflow_shell_and_probe_parse(self):
  d=yaml.safe_load((ROOT/'.github/workflows/catalog-quality-integration.yml').read_text())
  self.assertEqual(d['permissions'],{'contents':'read','actions':'read'})
  for s in d['jobs']['diagnostic']['steps']:
   if 'run' in s:subprocess.run(['bash','-n'],input=s['run'],text=True,check=True)
  swift=shutil.which('swiftc')
  if swift:subprocess.run([swift,'-frontend','-parse',str(ROOT/'probes/catalog-quality-integration/Diagnostic.swift')],check=True)
