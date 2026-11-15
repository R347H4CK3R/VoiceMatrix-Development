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
  for text in ['count == 2','stops.element(boundBy:0)','count == 0','save.label,"Saved"','PopoverDismissRegion','confirm.waitForNonExistence','confirm.tap()','select-character-diagnostic-neutral','Save to Files']:
   self.assertIn(text,s)
  swift=shutil.which('swiftc')
  if swift:subprocess.run([swift,'-frontend','-parse',str(ROOT/'VoiceMatrixUITests/CatalogHistoryUITests.swift')],check=True)

 def test_history_actions_do_not_use_automatic_form_row_button_style(self):
  s=(ROOT/'VoiceMatrix/CharacterLibraryView.swift').read_text()
  start=s.index('ForEach(library.speechHistory)')
  end=s.index('Button("Refresh / show more history")',start)
  self.assertIn('}.buttonStyle(.borderless)',s[start:end])

 def test_share_diagnostics_preserve_actual_export_gate(self):
  s=(ROOT/'VoiceMatrixUITests/CatalogHistoryUITests.swift').read_text()
  self.assertIn('XCTAssertTrue(sharePresented,',s)
  self.assertIn('XCUIApplication(bundleIdentifier:"com.apple.springboard")',s)
  self.assertIn('XCUIScreen.main.screenshot()',s)
  d=yaml.safe_load((ROOT/'.github/workflows/catalog-history-ui.yml').read_text())
  step=next(x for x in d['jobs']['ui']['steps'] if x.get('name')=='Retain owned simulator sharing diagnostics')
  self.assertIn('!cancelled()',step['if'])
  self.assertIn('log show --last 10m',step['run'])
  self.assertIn('sha256(p.read_bytes())',step['run'])
  self.assertIn("'com.voicematrix.app','data'",step['run'])
  self.assertIn('PRODUCT_BUNDLE_IDENTIFIER: com.voicematrix.app',(ROOT/'project.yml').read_text())

 def test_same_saved_byte_control_preserves_history_requirement(self):
  s=(ROOT/'VoiceMatrixUITests/CatalogHistoryUITests.swift').read_text()
  self.assertIn('if !sharePresented {',s)
  self.assertIn('speech-A8D5A8AA-2864-4BB3-BF19-AEE5CF424A16',s)
  self.assertIn('XCTAssertTrue(savedPresented,',s)
  self.assertIn('XCTAssertTrue(sharePresented,',s)
  self.assertIn('Same-byte sharing comparison',s)
  w=(ROOT/'.github/workflows/catalog-history-ui.yml').read_text()
  self.assertIn("root/'Documents/Recordings'",w)

 def test_history_sharing_has_its_own_form_row(self):
  s=(ROOT/'VoiceMatrix/CharacterLibraryView.swift').read_text()
  block=s[s.index('ForEach(library.speechHistory)'):s.index('Button("Refresh / show more history")')]
  self.assertIn('Group {\n                        VStack',block)
  self.assertIn('}\n                        if let retainedAudio',block)
 def test_share_gate_requires_visible_actionable_cells(self):
  s=(ROOT/'VoiceMatrixUITests/CatalogHistoryUITests.swift').read_text()
  self.assertIn('app.otherElements["ActivityListView"]',s)
  self.assertIn('sheet.cells.matching(NSPredicate(format:"label == %@",label))',s)
  self.assertIn('action.isHittable',s)
