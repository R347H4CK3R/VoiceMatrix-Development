import pathlib,tempfile,unittest
from tools import character_evidence as evidence
class EmbeddedSourceProofTests(unittest.TestCase):
 def test_bridge_resolver_and_dependency_pins_are_bound_without_generated_cache(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d)
   wanted=['VoiceMatrix/PythonRuntime/VMPythonRuntime.m','VoiceMatrix/PythonRuntime/VMPythonRuntime.h','python-resolver/voicematrix_resolver.py','tools/python-runtime/requirements-ios-resolver.txt','tools/python-runtime/prepare_python_runtime.py','VoiceMatrix/Resources/PythonRuntimeNotices/Python.txt']
   ignored=['python-resolver/__pycache__/voicematrix_resolver.pyc','.python-runtime/app_packages/yt_dlp/__init__.py','Vendors/Python/generated.py']
   for name in wanted+ignored:
    p=root/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture')
   actual={p.relative_to(root).as_posix() for p in evidence.embedded_source_paths(root)}
   self.assertEqual(actual,set(wanted))
 def test_actual_objc_and_runtime_pins_in_source_proof_inventory(self):
  root=pathlib.Path(__file__).resolve().parents[1]
  names={p.relative_to(root).as_posix() for p in evidence.embedded_source_paths(root)}
  for required in ['VoiceMatrix/PythonRuntime/VMPythonRuntime.m','VoiceMatrix/PythonRuntime/VoiceMatrix-Bridging-Header.h','python-resolver/voicematrix_resolver.py','tools/python-runtime/requirements-ios-resolver.txt','tools/python-runtime/notice-hashes.json']:
   self.assertIn(required,names)
  self.assertIn('paths += embedded_source_paths()', (root/'tools/character_evidence.py').read_text())
