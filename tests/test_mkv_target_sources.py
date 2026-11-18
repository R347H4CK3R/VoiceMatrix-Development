"""The diagnostic executes production acquisition and all its native dependencies."""
import pathlib, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class NativeExportTargets(unittest.TestCase):
 def test_diagnostic_contains_actual_export_dependencies(self):
  project = (ROOT/'project.yml').read_text()
  diagnostic = project.split('  LocalStudioDiagnostic:', 1)[1].split('schemes:', 1)[0]
  for name in ['LocalMediaAcquisition', 'LocalMKVExport', 'MP4SampleTable', 'MatroskaWriter']:
   self.assertIn('    - path: VoiceMatrix/' + name + '.swift', diagnostic)
