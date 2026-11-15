import pathlib,tempfile,unittest,runpy,os,sys,contextlib,shutil,subprocess,yaml,wave,array
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
class HistoryUITests(unittest.TestCase):
 def test_storage_checker_requires_real_saved_copy_and_preserved_reference(self):
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);container=p/'container';container.mkdir()
   source=p/'VoiceMatrix/Resources/F5TTS/UITestVoices/diagnostic-neutral/reference.wav';source.parent.mkdir(parents=True);
   with wave.open(str(source),'wb') as w:w.setparams((1,2,24000,0,'NONE','not compressed'));w.writeframes(array.array('h',[1000]*240).tobytes())
   def run(mode):
    with contextlib.chdir(p),patch.dict(os.environ,{'SIMULATOR_ID':'test-owned'}),patch.object(sys,'argv',['storage.py',mode]),patch('subprocess.check_output',return_value=str(container)+'\n'):
     runpy.run_path(str(ROOT/'probes/catalog-history-ui/storage.py'),run_name='__main__')
   run('seed')
   with self.assertRaises(AssertionError):run('seed')
   with self.assertRaises(AssertionError):run('verify')
   second=container/'Library/Application Support/CatalogSpeechChecks/B8D5A8AA-2864-4BB3-BF19-AEE5CF424A16'
   secondBytes=(second/'speech.wav').read_bytes()
   shutil.rmtree(container/'Library/Application Support/CatalogSpeechChecks/A8D5A8AA-2864-4BB3-BF19-AEE5CF424A16');shutil.rmtree(second)
   with self.assertRaises(AssertionError):run('verify')
   saved=container/'Documents/Recordings/saved.wav';saved.parent.mkdir(parents=True);shutil.copyfile(source,saved)
   with self.assertRaises(AssertionError):run('verify')
   ref=container/'Library/Application Support/CharacterReferences/example/reference.wav';ref.parent.mkdir(parents=True);shutil.copyfile(source,ref)
   with self.assertRaises(AssertionError):run('verify')
   (saved.parent/'second.wav').write_bytes(secondBytes);run('verify')
   saved.write_bytes(b'corrupted')
   with self.assertRaises(AssertionError):run('verify')
 def test_workflow_and_scope(self):
  d=yaml.safe_load((ROOT/'.github/workflows/catalog-history-ui.yml').read_text())
  self.assertEqual(d['permissions'],{'contents':'read'})
  for step in d['jobs']['ui']['steps']:
   if 'run' in step:subprocess.run(['bash','-n'],input=step['run'],text=True,check=True)
  s=(ROOT/'VoiceMatrixUITests/CatalogHistoryUITests.swift').read_text()
  for text in ['stop.waitForExistence','save.label,"Saved"','app.buttons["Cancel"].tap()','confirm.tap()','select-character-diagnostic-neutral','Save to Files']:
   self.assertIn(text,s)
  swift=shutil.which('swiftc')
  if swift:subprocess.run([swift,'-frontend','-parse',str(ROOT/'VoiceMatrixUITests/CatalogHistoryUITests.swift')],check=True)
