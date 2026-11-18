import json,tempfile,unittest
from pathlib import Path
from tools.seed_separation_handoff_ui import seed,check,paths,fixture,VALID,CORRUPT
ROOT=Path(__file__).resolve().parents[1]
class HandoffFixtureTests(unittest.TestCase):
    def test_seed_and_reused_copy_preserve_originals_and_reject_processing(self):
        with tempfile.TemporaryDirectory() as td:
            container=Path(td);seed(container);root,jobs=paths(container)
            with self.assertRaises(FileExistsError):seed(container)
            with self.assertRaises(AssertionError):check(container)
            vocal,_,receipt=fixture(VALID)
            (root/('Reference-'+VALID+'-'+receipt['vocalsSHA256']+'.wav')).write_bytes(vocal)
            check(container)
            jobs.mkdir();(jobs/'unexpected-job.json').write_text('{}')
            with self.assertRaises(AssertionError):check(container)
    def test_corrupt_pair_remains_bad_and_original_changes_detected(self):
        with tempfile.TemporaryDirectory() as td:
            container=Path(td);seed(container);root,_=paths(container)
            vocal,_,receipt=fixture(VALID)
            (root/('Reference-'+VALID+'-'+receipt['vocalsSHA256']+'.wav')).write_bytes(vocal)
            bad=root/('Result-'+CORRUPT)/('Vocals-'+CORRUPT+'.wav')
            self.assertNotEqual(bad.read_bytes(),fixture(CORRUPT)[0])
            (root/'UI-original.wav').write_bytes(b'changed')
            with self.assertRaises(AssertionError):check(container)
    def test_seeded_test_only_runs_in_existing_seeded_batch(self):
        workflow=(ROOT/'.github/workflows/character-ui-smoke.yml').read_text()
        runs=[x for x in workflow.splitlines() if 'xcodebuild test-without-building ' in x]
        self.assertEqual(len(runs),4)
        self.assertIn('VocalSeparationUITests/testSeparationRequiresExplicitInputAndKeepsExistingRoutes',runs[0])
        self.assertIn('VocalSeparationUITests/testSeededVocalsHandoffRequiresFreshAuthorizationAcrossNavigation',runs[3])
        self.assertNotIn('VocalSeparationUITests/testSeeded',runs[0])
