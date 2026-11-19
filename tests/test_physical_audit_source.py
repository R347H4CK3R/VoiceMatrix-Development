import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "probes/physical-audit"


class PhysicalAuditSourceTests(unittest.TestCase):
    def test_renders_distinct_audit_without_changing_production_source(self):
        with tempfile.TemporaryDirectory() as path:
            path = Path(path)
            subprocess.run([sys.executable, str(PROBE / "prepare.py"), str(path / "audit")],
                           cwd=ROOT, check=True)
            audit = path / "audit"
            spec = (audit / "project.yml").read_text()
            swift = (audit / "AuditChecks.swift").read_text()
            self.assertIn("com.voicematrix.physicalaudit", spec)
            self.assertNotIn("com.voicematrix.app", spec)
            self.assertIn("- App.swift", spec)
            self.assertIn("- LaptopSettings.json", spec)
            self.assertIn("- .physical-audit-src/ProductionViews.swift", spec)
            preserved = (audit / "ProductionViews.swift").read_text()
            self.assertEqual(preserved.replace("struct VoiceMatrixApp", "@main struct VoiceMatrixApp", 1),
                             (ROOT / "VoiceMatrix/App.swift").read_text())
            self.assertIn("UIFileSharingEnabled: false", spec)
            self.assertNotIn("XCTest", swift)
            self.assertIn("try auditEqual", swift)
            for required in ("studio.resume", "verifyRetainedClipSource",
                             "LocalMatroskaWorkflow.validatePublished",
                             "library.speak", "asr.transcribe", "0.1", "phaseOnePID"):
                self.assertIn(required, swift)
            self.assertEqual({p.name for p in audit.iterdir()}, {"AuditChecks.swift", "ProductionViews.swift", "project.yml"})

    def test_rejects_existing_output(self):
        with tempfile.TemporaryDirectory() as path:
            result = subprocess.run([sys.executable, str(PROBE / "prepare.py"), path],
                                    cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("new output directory", result.stderr)

    def test_pin_mismatch_is_rejected_before_transform(self):
        spec = importlib.util.spec_from_file_location("audit_prepare", PROBE / "prepare.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            module.render_runner("not the approved proof")
        with self.assertRaisesRegex(ValueError, "SHA-256"):
            module.render_project("not the approved production target")

    def test_ui_handoff_is_offline_explicit_and_report_is_redacted(self):
        ui = (PROBE / "AuditApp.swift").read_text()
        for required in ("targetEnvironment(simulator)", "isiOSAppOnMac", "phaseOnePID",
                         "Run offline phase 1", "Run offline phase 2",
                         "fileExporter", "AllowlistedAuditReport", "phase-two-started"):
            self.assertIn(required, ui)
        report = ui[ui.index("struct AllowlistedAuditReport"):ui.index("struct AuditExport")]
        for private in ("phaseOnePID", "phaseTwoPID", "jobID", "attemptID", "voiceID", "URL", "transcript"):
            self.assertNotIn(private, report)
        for media in (".wav", ".mov", ".mp4", ".mkv"):
            self.assertNotIn(media, report)


if __name__ == "__main__":
    unittest.main()
