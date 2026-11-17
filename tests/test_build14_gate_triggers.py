"""Every mandatory gate must evaluate the combined runtime packaging correction."""
import fnmatch
from pathlib import Path
import unittest
import yaml
ROOT = Path(__file__).resolve().parents[1]
REQUIRED = ('reference-context-full-route reference-context-human-holdouts local-pipeline-diagnostic native-app native-character-folder character-ui-smoke bundled-asr-diagnostic queue-processor native-queue queue-recovery raw-overlap-policy overlap-integration14 ondevice-resolver-app iphone-build14').split()
CORRECTION_PATHS = ['tools/python-runtime/install_python_runtime.sh', 'tools/python-runtime/verify_python_bundle.py', 'tests/python-packaging/test_runtime_bundle.py', 'tests/test_build14_gate_triggers.py', '.github/workflows/ios.yml', 'tests/test_source_workflow_dependencies.py'] + ['.github/workflows/' + n + '.yml' for n in ['queue-processor','queue-recovery','local-pipeline-diagnostic','native-app','character-ui-smoke','bundled-asr-diagnostic','native-queue']]
class Build14GateTriggersTests(unittest.TestCase):
    def test_combined_correction_triggers_every_required_gate(self):
        branch = 'feature/voicematrix-ondevice-ytdlp'
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
            for changed in ('VoiceMatrix/App.swift','python-resolver/resolver.py','tools/python-runtime/install_python_runtime.sh','project.yml','tests/test_preview_build14.py','.github/workflows/iphone-build14.yml'):
                with self.subTest(workflow=name,changed=changed):
                    self.assertTrue(any(fnmatch.fnmatchcase(changed,p) for p in paths))
