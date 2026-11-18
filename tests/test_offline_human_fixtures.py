"""Real preparation must survive fixture-server outages without changing audio."""
import hashlib
import json
import pathlib
import runpy
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPTS = ['full-retained-speaker-route', 'second-complete-speaker-route', 'overlap-stress']

class OfflineHumanFixturesTests(unittest.TestCase):
    def run_prepare(self, root, script, output):
        with patch.object(sys, 'argv', ['prepare.py', str(output)]), patch('urllib.request.urlopen', side_effect=RuntimeError('fixture server unavailable')):
            runpy.run_path(str(root / 'probes' / script / 'prepare.py'), run_name='__main__')

    def test_real_preparation_works_offline_and_preserves_original_flac(self):
        sources = json.loads((ROOT / 'probes/human-local-studio/sources.json').read_text())
        with tempfile.TemporaryDirectory() as tmp:
            for i, script in enumerate(SCRIPTS):
                out = pathlib.Path(tmp) / script
                self.run_prepare(ROOT, script, out)
                for src in sources if i == 2 else [sources[i]]:
                    flac = out / (src['id'] + '.flac' if i == 2 else 'complete-source.flac')
                    self.assertEqual(hashlib.sha256(flac.read_bytes()).hexdigest(), src['sourceSHA256'])
                if i == 2:
                    self.assertEqual(len(json.loads((out / 'manifest.json').read_text())['cases']), 5)
                else:
                    self.assertGreater(json.loads((out / 'fixture.json').read_text())['duration'], 8)

    def test_modified_corpus_fails_closed_without_network_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            shutil.copytree(ROOT / 'probes', root / 'probes')
            corpus = root / 'tests/fixtures/licensed-human-source'
            corpus.mkdir(parents=True)
            for name in ['2961-960-0003', '4507-16021-0031']:
                (corpus / (name + '.flac')).write_bytes(b'not the pinned recording')
            for script in SCRIPTS:
                with self.assertRaises((ValueError, AssertionError)):
                    self.run_prepare(root, script, root / script)
