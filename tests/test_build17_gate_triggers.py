"""Every mandatory gate must evaluate the privacy-safe diagnostics update."""
import fnmatch
from pathlib import Path
import unittest
import yaml
ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ('reference-context-full-route reference-context-human-holdouts local-pipeline-diagnostic native-app native-character-folder character-ui-smoke bundled-asr-diagnostic queue-processor native-queue queue-recovery raw-overlap-policy overlap-integration17 ondevice-resolver-app speaker-handoff-ui iphone-build17').split()
CORRECTION_PATHS = ['project.yml', 'VoiceMatrix/LocalMediaAcquisition.swift', 'VoiceMatrix/OnDeviceYouTubeResolver.swift', 'tools/python-runtime/verify_python_bundle.py', 'tests/test_download_diagnostics.py', '.github/workflows/iphone-build17.yml']
class Build17GateTriggersTests(unittest.TestCase):
    def test_combined_correction_triggers_every_required_gate(self):
        branch = 'feature/voicematrix-download-diagnostics'
        for name in REQUIRED:
            with self.subTest(workflow=name):
                d = yaml.safe_load((ROOT / '.github/workflows' / (name+'.yml')).read_text())
                push = (d.get('on') or d.get(True))['push']
                self.assertTrue(any(fnmatch.fnmatchcase(branch, p) for p in push.get('branches', ['*'])))
                self.assertFalse(any(fnmatch.fnmatchcase(branch, p) for p in push.get('branches-ignore', [])))
                self.assertTrue(any(fnmatch.fnmatchcase(f,p) for f in CORRECTION_PATHS for p in push.get('paths',['**'])))
    def test_platform_and_recovery_cover_runtime_app_and_version_changes(self):
        for name in ('queue-processor','queue-recovery'):
            d = yaml.safe_load((ROOT / '.github/workflows' / (name+'.yml')).read_text())
            paths = (d.get('on') or d.get(True))['push']['paths']
            for changed in ('VoiceMatrix/App.swift','python-resolver/resolver.py','tools/python-runtime/install_python_runtime.sh','project.yml'):
                with self.subTest(workflow=name,changed=changed):
                    self.assertTrue(any(fnmatch.fnmatchcase(changed,p) for p in paths))
