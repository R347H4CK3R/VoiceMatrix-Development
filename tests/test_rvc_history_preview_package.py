"""Artifact-only sibling preserves all build17 gates and immutable app provenance."""
import copy
from pathlib import Path
import unittest
import yaml
from tools.test_shell import check_bash_syntax

ROOT=Path(__file__).resolve().parents[1]
TARGET='3783d72ce5798bd8230784c806eebe06dfa87ccb'
PREFIX='''set -e
actual_source=$(git rev-parse HEAD)
test "$actual_source" = "$TARGET_SOURCE"
# Build evidence must name the immutable app source, not this workflow commit.
export GITHUB_SHA="$actual_source"
'''

class HistoryPackageTests(unittest.TestCase):
    def setUp(self):
        self.base=yaml.safe_load((ROOT/'.github/workflows/iphone-build17.yml').read_text())
        self.preview=yaml.safe_load((ROOT/'.github/workflows/iphone-rvc-history-preview.yml').read_text())
    def test_artifact_only_trigger_and_permissions(self):
        self.assertEqual(self.preview['on'],{'push':{'branches':['packaging/rvc-history-preview']},'workflow_dispatch':None})
        self.assertEqual(self.preview['permissions'],{'contents':'read','actions':'read'})
        self.assertEqual(self.preview['env'],{'TARGET_SOURCE':TARGET,'PACKAGING_WORKFLOW_COMMIT':'${{ github.sha }}'})
        self.assertEqual(self.base['on']['push']['branches'],['preview/voicematrix-build17','feature/voicematrix-download-diagnostics'])
    def test_every_existing_gate_is_preserved(self):
        normalized=copy.deepcopy(self.preview['jobs'])
        for job in normalized.values():
            for step in job['steps']:
                if step.get('uses')=='actions/checkout@v4':
                    self.assertEqual(step.pop('with'),{'ref':TARGET})
                if 'run' in step:
                    self.assertTrue(step['run'].startswith(PREFIX))
                    run=step['run'][len(PREFIX):]
                    run=run.replace('VoiceMatrix-0.4.14-build17-RVC-history-preview-3783d72.ipa','VoiceMatrix-0.4.14-build17.ipa')
                    run=run.replace("sourceCommit=os.environ['GITHUB_SHA'],packagingWorkflowCommit=os.environ['PACKAGING_WORKFLOW_COMMIT'],previewLabel='durable-rvc-history-artifact-only',", "sourceCommit=os.environ['GITHUB_SHA'],")
                    run=run.replace("purpose='Unsigned durable RVC history preview; packaging and asset inspection only'", "purpose='Unsigned iPhone preview; packaging and asset inspection only'")
                    step['run']=run
                if step.get('uses') in ('actions/upload-artifact@v4','actions/download-artifact@v4'):
                    self.assertTrue(step['with']['name'].startswith('RVC-history-preview-'))
                    step['with']['name']=step['with']['name'].removeprefix('RVC-history-preview-')
                    if 'path' in step['with']:
                        step['with']['path']=step['with']['path'].replace('VoiceMatrix-0.4.14-build17-RVC-history-preview-3783d72.ipa','VoiceMatrix-0.4.14-build17.ipa')
        self.assertEqual(normalized,self.base['jobs'])
    def test_shell_and_status_bind_both_commits(self):
        for job in self.preview['jobs'].values():
            for step in job['steps']:
                if 'run' in step:
                    check_bash_syntax(step['run'])
                    self.assertNotIn('gh release',step['run'])
        status=next(s['run'] for s in self.preview['jobs']['ipa']['steps'] if 'packaging-status.json' in s.get('run',''))
        self.assertIn("packagingWorkflowCommit=os.environ['PACKAGING_WORKFLOW_COMMIT']",status)
        self.assertIn("sourceCommit=os.environ['GITHUB_SHA']",status)
        self.assertIn('physicalDeviceVerified=False',status)
        self.assertIn('likenessVerified=False',status)
