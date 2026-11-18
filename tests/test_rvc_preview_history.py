"""Actual native filesystem tests for durable RVC preview history.

No model inference is faked; synthetic PCM verifies storage/integrity behavior only.
macOS compilation/test failures are failures, not successful skips.
"""
import pathlib
import platform
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class HistorySourceTests(unittest.TestCase):
    def test_production_store_and_native_probe_exist(self):
        self.assertTrue((ROOT / 'VoiceMatrix/RVCResultHistory.swift').is_file())
        self.assertTrue((ROOT / 'probes/rvc-result-history/main.swift').is_file())

    def test_ui_uses_verified_snapshot_and_durable_commit(self):
        studio=(ROOT/'VoiceMatrix/RVCOnDeviceStudio.swift').read_text()
        self.assertIn('.snapshot(receipt,cache:',studio)
        self.assertIn('output=snapshot',studio)
        self.assertNotIn('output=destination',studio)
        self.assertNotIn('removeItem(at:destination)',studio)
        self.assertIn('finishCommitted(ticket:ticket)',studio)
        self.assertIn('completedButUnindexed',studio)
        self.assertIn('refresh();refreshHistory()',studio)
        self.assertIn('selectHistory(receipt,audio:audio)',(ROOT/'VoiceMatrix/RVCOnDeviceView.swift').read_text())


@unittest.skipUnless(platform.system() == 'Darwin', 'requires macOS Swift and CryptoKit')
class NativeHistoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.workspace = tempfile.TemporaryDirectory(prefix='rvc-history-native-')
        cls.addClassCleanup(cls.workspace.cleanup)
        cls.binary = pathlib.Path(cls.workspace.name) / 'history-probe'
        sources = ['VoiceMatrix/RVCPreviewState.swift', 'VoiceMatrix/RetainedMediaReader.swift', 'VoiceMatrix/RVCResultHistory.swift',
                   'probes/rvc-result-history/main.swift']
        subprocess.run(['swiftc', '-parse-as-library', *[str(ROOT / p) for p in sources],
                        '-o', str(cls.binary)], check=True, timeout=180)

    def run_case(self, name):
        with tempfile.TemporaryDirectory(prefix='rvc-history-case-') as td:
            completed = subprocess.run([str(self.binary), name, td], text=True, capture_output=True, timeout=30)
            self.assertEqual(completed.returncode, 0, completed.stdout + '\n' + completed.stderr)
            self.assertIn('HISTORY_CASE_PASSED ' + name, completed.stdout)

    def test_interrupted_staging_and_corrupt_cache_do_not_block_recovery(self): self.run_case('snapshot-crash')
    def test_mixed_history_and_receipt_publication_failure_preserve_valid_results(self): self.run_case('mixed-history')
    def test_commit_state_wins_late_cancellation(self): self.run_case('commit-state')
    def test_publish_relaunch_list_and_verify(self): self.run_case('roundtrip')
    def test_corrupted_output_is_rejected_without_deletion(self): self.run_case('corruption')
    def test_changed_receipt_invalidates_stale_selection(self): self.run_case('receipt-change')
    def test_late_cancellation_keeps_committed_receipt(self): self.run_case('late-cancellation')
    def test_untrusted_receipt_path_never_escapes_root(self): self.run_case('traversal')
    def test_symlinks_and_fifos_are_rejected_without_blocking(self): self.run_case('unsafe-files')
    def test_unindexed_and_unrelated_files_remain_untouched(self): self.run_case('unindexed')
    def test_receipt_overwrite_is_refused_without_data_loss(self): self.run_case('overwrite')
    def test_invalid_metadata_and_settings_fail_closed(self): self.run_case('metadata')
    def test_incomplete_or_invalid_wav_is_not_published(self): self.run_case('invalid-wav')
    def test_listing_and_receipt_size_limits_are_enforced(self): self.run_case('bounds')
    def test_cancelled_publication_preserves_completed_output(self): self.run_case('cancellation')
    def test_repeated_open_reuses_and_reverifies_copy(self): self.run_case('snapshot-reuse')
    def test_verified_selection_snapshot_survives_original_changes(self): self.run_case('snapshot')


if __name__ == '__main__': unittest.main()
