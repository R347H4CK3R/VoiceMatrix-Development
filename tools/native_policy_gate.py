"""Execute actual Foundation policies; a missing compiler or skip fails this CI gate.

This is not speech inference, simulator UI, or physical-device verification.
"""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
# Direct execution must import this repository's tests, not a site-package named tests.
sys.path.insert(0, str(ROOT))
CHECKS = (
    'tests.test_local_studio_journal.LocalJournalTests.test_real_foundation_journal',
    'tests.test_native_acquisition.NativeAcquisitionTests.test_real_swift_url_parser_budget_policy',
    'tests.test_local_sound_quality.LocalSoundQualityTests.test_swift_independent_scores_and_coverage_policy',
    'tests.test_speaker_similarity.SimilarityTests.test_native_similarity_math',
)

def run(suite, stream=None):
    result = unittest.TextTestRunner(stream=stream, verbosity=2).run(suite)
    return 0 if result.testsRun > 0 and result.wasSuccessful() and not result.skipped else 1

if __name__ == '__main__':
    sys.exit(run(unittest.defaultTestLoader.loadTestsFromNames(CHECKS)))
