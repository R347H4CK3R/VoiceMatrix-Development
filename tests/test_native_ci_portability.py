"""Keep the broad native suite runnable without assuming Linux tools on macOS."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class NativeCIPortabilityTests(unittest.TestCase):
 def test_apple_profile_test_uses_system_cryptokit(self):
  source=(ROOT/'tests/test_direct_voice_profile.py').read_text()
  self.assertIn("if sys.platform != 'darwin':",source)
 def test_vector_hash_uses_platform_native_utility(self):
  source=(ROOT/'tests/native/RVCDiskVectorChecks.swift').read_text()
  self.assertIn('#if os(macOS)',source)
  self.assertIn('/usr/bin/shasum',source)
  self.assertIn('["-a","256","-"]',source)
 def test_broad_workflow_installs_declared_python_dependencies(self):
  workflow=(ROOT/'.github/workflows/native-character-folder.yml').read_text()
  self.assertIn('python3 -m pip install -r tests/requirements-native.txt',workflow)
  requirements=(ROOT/'tests/requirements-native.txt').read_text()
  self.assertIn('numpy==',requirements)
  self.assertIn('PyYAML==',requirements)
