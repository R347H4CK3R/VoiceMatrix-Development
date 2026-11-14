"""Linux/macOS portable studio regressions; skips are failures, not verification.

Uses real Foundation filesystem checks and explicitly bounded test doubles where
Apple UI/audio frameworks are unavailable. Does not build an IPA or run models.
"""
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from tools.native_policy_gate import run

CHECKS = (
    "tests.test_retained_media_reader",
    "tests.test_local_studio_journal",
    "tests.test_local_completion_transaction",
    "tests.test_local_snapshot_recovery",
    "tests.test_local_resume_receipts",
    "tests.test_local_studio_engine_preflight",
    "tests.test_local_video_studio",
    "tests.test_native_acquisition",
    "tests.test_character_names",
    "tests.test_recording_import_progress",
    "tests.test_recorder_completion",
    "tests.test_reference_playback_ownership",
)

if __name__ == "__main__":
    print("Portable studio checks only: no iOS build, model inference, physical device or likeness verification.", flush=True)
    sys.exit(run(unittest.defaultTestLoader.loadTestsFromNames(CHECKS)))
