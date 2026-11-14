"""Actual Foundation filesystem behavior; no iOS/audio/model claim."""
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

class RetainedMediaReaderTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("swiftc"), "Swift compiler unavailable")
    def test_bounded_reads_preserve_sources(self):
        with tempfile.TemporaryDirectory() as folder:
            exe = str(Path(folder) / "checks")
            subprocess.run(["swiftc", "-parse-as-library",
                str(ROOT / "VoiceMatrix/RetainedMediaReader.swift"),
                str(ROOT / "tests/native/RetainedMediaReaderChecks.swift"),
                "-o", exe], check=True, timeout=120, capture_output=True, text=True)
            result = subprocess.run([exe], check=True, timeout=30, capture_output=True, text=True)
            self.assertIn("Retained media checks passed", result.stdout)

    def test_resume_and_acquisition_use_bounded_reader(self):
        studio = (ROOT / "VoiceMatrix/LocalVideoStudio.swift").read_text()
        recovery = studio.split("let digestTask = Task.detached", 1)[1].split("let actualHash", 1)[0]
        self.assertIn("RetainedMediaReader.read(retained, maximumBytes: LocalMediaURLPolicy.maximumBytes)", recovery)
        self.assertIn("catch is CancellationError", recovery)
        self.assertNotIn("FileHandle(forReadingFrom:", recovery)
        acquisition = (ROOT / "VoiceMatrix/LocalMediaAcquisition.swift").read_text()
        digest = acquisition.split("private static func digest", 1)[1].split("static func merge", 1)[0]
        self.assertIn("RetainedMediaReader.read(url, maximumBytes: LocalMediaURLPolicy.maximumBytes)", digest)
        self.assertIn("catch is CancellationError", digest)
