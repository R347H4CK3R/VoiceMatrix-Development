import contextlib
import hashlib
import importlib.util
import io
import json
import pathlib
import shutil
import sys
import tempfile
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'tests/fixtures/licensed-human-holdouts'

def prepare_module():
    spec = importlib.util.spec_from_file_location('offline_holdout_prepare', ROOT / 'probes/reference-context-human-holdouts/prepare.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class OfflineHumanHoldoutTests(unittest.TestCase):
    def test_exact_original_bytes_and_metadata(self):
        module = prepare_module()
        metadata = json.loads((FIXTURES / 'provenance.json').read_text())
        self.assertEqual(metadata['sources'], module.sources())
        self.assertEqual(metadata['artifactID'], 14396650003)
        for source in module.sources():
            data = (FIXTURES / (source['id'] + '.flac')).read_bytes()
            self.assertEqual(len(data), source['sourceBytes'])
            self.assertEqual(hashlib.sha256(data).hexdigest(), source['sourceSHA256'])

    @unittest.skipUnless(shutil.which('ffmpeg'), 'complete source decoding requires ffmpeg')
    def test_prepares_all_eight_cases_without_network(self):
        module = prepare_module()
        with tempfile.TemporaryDirectory() as td, mock.patch('urllib.request.urlopen', side_effect=AssertionError('network forbidden')) as network:
            output = pathlib.Path(td) / 'prepared'
            with mock.patch.object(sys, 'argv', ['prepare.py', str(output)]), contextlib.redirect_stdout(io.StringIO()):
                module.main()
            network.assert_not_called()
            manifest = json.loads((output / 'manifest.json').read_text())
            self.assertEqual(manifest['sources'], module.sources())
            self.assertEqual(len(manifest['cases']), 8)
            self.assertTrue(all(r['prepared'] for r in manifest['preparationAttempts']))
            for source in module.sources():
                cases = [c for c in manifest['cases'] if c['id'].startswith(source['id'] + '-')]
                self.assertEqual([c['mode'] for c in cases], ['baseline', 'reference'])
                self.assertEqual(cases[0]['file'], cases[1]['file'])
                self.assertEqual(cases[0]['sha256'], cases[1]['sha256'])
                self.assertEqual(cases[0]['expected'], source['referenceText'])
                module.validate_source((output / (source['id'] + '.flac')).read_bytes(), source)

    @unittest.skipUnless(shutil.which('ffmpeg'), 'complete source decoding requires ffmpeg')
    def test_missing_corrupt_or_changed_metadata_fail_closed_without_fetch(self):
        for failure in ('missing', 'corrupt', 'metadata'):
            with self.subTest(failure=failure), tempfile.TemporaryDirectory() as td:
                module = prepare_module()
                fixture = pathlib.Path(td) / 'fixtures'
                shutil.copytree(FIXTURES, fixture)
                source = module.sources()[0]
                file = fixture / (source['id'] + '.flac')
                if failure == 'missing': file.unlink()
                elif failure == 'corrupt': file.write_bytes(b'corrupt')
                else:
                    p = fixture / 'provenance.json'
                    record = json.loads(p.read_text())
                    record['sources'][0]['referenceText'] += ' CHANGED'
                    p.write_text(json.dumps(record))
                output = pathlib.Path(td) / 'prepared'
                with mock.patch.object(module, 'FIXTURES', fixture, create=True), mock.patch('urllib.request.urlopen', side_effect=AssertionError('network forbidden')) as network, mock.patch.object(sys, 'argv', ['prepare.py', str(output)]):
                    with self.assertRaises(SystemExit): module.main()
                    network.assert_not_called()
                manifest = json.loads((output / 'manifest.json').read_text())
                self.assertFalse(manifest['preparationAttempts'][0]['prepared'])
                self.assertTrue(manifest['preparationAttempts'][0]['error'])
                self.assertFalse((output / (source['id'] + '-original.wav')).exists())
