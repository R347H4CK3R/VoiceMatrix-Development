from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MKVPythonBridgeContractTests(unittest.TestCase):
    def test_two_fixed_operations_share_the_serialized_worker(self):
        runtime = ROOT / "VoiceMatrix/PythonRuntime"
        header = (runtime / "VMPythonRuntime.h").read_text()
        source = (runtime / "VMPythonRuntime.m").read_text()
        self.assertIn("decideMKVStageJSON:", header)
        self.assertIn("operation:VMOperationResolve completion:completion", source)
        self.assertIn("operation:VMOperationMKVStage completion:completion", source)
        self.assertIn('"voicematrix_mkv_stage" : "voicematrix_resolver"', source)
        self.assertIn('"decide" : "resolve"', source)
        self.assertEqual(source.count("dispatch_async(vmQueue,"), 1)
        self.assertIn("VMCancelled(context)", source)
        self.assertIn("stage ? 4096 : 16384", source)
        self.assertIn("stage ? 4096 : 1024*1024", source)
        self.assertIn("PyUnicode_DecodeUTF8", source)

    def test_only_named_stage_module_is_copied_and_byte_verified(self):
        scripts = ROOT / "tools/python-runtime"
        prepare = (scripts / "prepare_app_python.py").read_text()
        verify = (scripts / "verify_python_bundle.py").read_text()
        self.assertIn("('voicematrix_resolver.py','voicematrix_mkv_stage.py')", prepare)
        self.assertIn("('voicematrix_resolver.py','voicematrix_mkv_stage.py')", verify)
        self.assertIn("resource('app_packages/'+module,(ROOT/'python-resolver'/module).read_bytes())", verify)
        self.assertIn("relative in app_modules", verify)
