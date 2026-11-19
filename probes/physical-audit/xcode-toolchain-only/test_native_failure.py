import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("native_failure", HERE / "native_failure.py")
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class NativeBuildFailureTests(unittest.TestCase):
    def test_allowlist_reports_only_categories_no_paths_or_diagnostics(self):
        representative = (
            "xcodebuild: error: Could not open connection to build service /private/unpublished\n"
            "/home/private/Secret.swift:19:5: error: cannot find 'secret-token' in scope\n"
        )
        report = probe.classify(representative, 74)
        self.assertEqual(report["exitCode"], 74)
        self.assertIn("xcbuild-service-ipc", report["categories"])
        self.assertIn("swift-symbol-resolution", report["categories"])
        self.assertNotIn("private", str(report))
        self.assertNotIn("secret-token", str(report))
        self.assertNotIn("Secret.swift", str(report))

    def test_unknown_failure_does_not_claim_ipc_or_compiler(self):
        report = probe.classify("uninformative log", 74)
        self.assertEqual(report["categories"], ["unclassified"])
        self.assertFalse(report["swiftDiagnosticSeen"])

    def test_unreadable_log_does_not_expose_exception_or_path(self):
        with patch.object(probe, "read_bounded", side_effect=PermissionError("/secret/runner/path")):
            report = probe.failure_report(Path("/secret/runner/path"), 74)
        self.assertEqual(report, {"exitCode": 74, "categories": ["unreadable-build-log"], "swiftDiagnosticSeen": False})

    def test_log_read_is_bounded_and_missing_log_is_distinct(self):
        with tempfile.TemporaryDirectory() as td:
            log = Path(td) / "private.log"
            self.assertIsNone(probe.read_bounded(log))
            log.write_bytes(b"head" + b"x" * (probe.MAX_BYTES + 16) + b"tail")
            content = probe.read_bounded(log)
            self.assertLessEqual(len(content), probe.MAX_BYTES + 1)
            self.assertTrue(content.startswith("head") and content.endswith("tail"))


if __name__ == "__main__":
    unittest.main()
