import hashlib, importlib.util, pathlib, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'probes/leading-padding-full-route/stage.py'
def module():
 s=importlib.util.spec_from_file_location('stage_padding',SCRIPT);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
class StageTests(unittest.TestCase):
 def test_implemented(self):self.assertTrue(SCRIPT.is_file(),'Diagnostic staging missing')
 def test_exact_change_and_drift_rejected(self):
  self.assertTrue(SCRIPT.is_file(),'Diagnostic staging missing');m=module();raw=(ROOT/'VoiceMatrix/OnDeviceTranscription.swift').read_bytes();out=m.patch(raw)
  self.assertEqual(hashlib.sha256(raw).hexdigest(),m.SOURCE_SHA)
  self.assertEqual(out.replace(m.NEW,m.OLD).replace(m.HELPER,b''),raw)
  for altered in [raw+b'\n',raw.replace(b'45 seconds',b'46 seconds')]:
   with self.assertRaises(ValueError):m.patch(altered)
  self.assertIn(b'inputDigest(file, byteCount: size, matching: inputSHA256)',out)
 def test_project_only_diagnostic_target(self):
  self.assertTrue(SCRIPT.is_file(),'Diagnostic staging missing');m=module();raw=(ROOT/'project.yml').read_bytes();out=m.project(raw)
  self.assertEqual(out.replace(m.NEW_PATH,m.OLD_PATH),raw)
  self.assertEqual(out.count(m.NEW_PATH),1)
  with self.assertRaises(ValueError):m.project(raw+b'\n')
 def test_staging_preserves_shipping_and_rejects_overwrite(self):
  self.assertTrue(SCRIPT.is_file(),'Diagnostic staging missing');m=module()
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);(root/'VoiceMatrix').mkdir();source=(ROOT/'VoiceMatrix/OnDeviceTranscription.swift').read_bytes();(root/'VoiceMatrix/OnDeviceTranscription.swift').write_bytes(source);(root/'project.yml').write_bytes((ROOT/'project.yml').read_bytes())
   m.stage(root);self.assertEqual((root/'VoiceMatrix/OnDeviceTranscription.swift').read_bytes(),source)
   self.assertTrue((root/'padding-staged/patch.diff').is_file())
   with self.assertRaises(FileExistsError):m.stage(root)
class WorkflowTests(unittest.TestCase):
 def test_exact_production_untouched_and_workflow_limits(self):
  import yaml,subprocess
  m=module();self.assertEqual(m.SOURCE_SHA,'758ed706e92fc3da63cdfb6048fb65afcd13475ece8534381bbd2f0050e06ae6')
  raw=(ROOT/'VoiceMatrix/OnDeviceTranscription.swift').read_bytes();self.assertEqual(m.sha(m.patch(raw)),m.PATCHED_SHA)
  original=m.HELPER
  try:
   m.HELPER+=b'\n'
   with self.assertRaises(ValueError):m.patch(raw)
  finally:m.HELPER=original
  workflow=yaml.safe_load((ROOT/'.github/workflows/leading-padding-full-route.yml').read_text());self.assertEqual(workflow['permissions']['contents'],'read')
  runs='\n'.join(s.get('run','') for s in workflow['jobs']['diagnostic']['steps'])
  self.assertIn('xcodegen generate --spec diagnostic-leading.yml',runs);self.assertIn('probes/two-complete-readers/check.py',runs);self.assertIn('x["newSpeechWordErrorRate"]==0',runs)
  self.assertIn('(deny network*)',runs)
  self.assertNotIn('gh release',runs)
  pinned={'Diagnostic.swift': '4920d09f1087ba5d36312c96b97b9a6251ee46be6d0ec5bbdb2a51c012e42386', 'check.py': 'ea0c944de8f9a6f71314a06520408138394ae987e4a2e3938b9edb01fb672180', 'prepare.py': '4beb4c34d83b26f1c327691ed33296fdcd561275753c842babb11d67e56b2507', 'staged_changes.py': '485a8b25fcd973c634a88192796f08543cf3b8a5bb95bd68ea0dbe3764e7773a'}
  for name,expected in pinned.items():
   self.assertEqual(hashlib.sha256((ROOT/'probes/two-complete-readers'/name).read_bytes()).hexdigest(),expected)
