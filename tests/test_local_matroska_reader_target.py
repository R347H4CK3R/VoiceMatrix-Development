"""Host-native fixture gate; hostile input coverage also runs in VoiceMatrixTests."""
import platform
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LocalMatroskaReaderTarget(unittest.TestCase):
    def test_reader_and_writer_roundtrip_suite_are_present(self):
        self.assertTrue((ROOT / "VoiceMatrix/LocalMatroskaReader.swift").is_file(),
                        "Strict reader not implemented")
        self.assertTrue((ROOT / "VoiceMatrixTests/LocalMatroskaReaderTests.swift").is_file())

    @unittest.skipUnless(platform.system() == "Darwin" and shutil.which("swiftc") and shutil.which("ffmpeg"),
                         "requires Apple Swift/CryptoKit and ffmpeg for host fixture")
    def test_real_compressed_packets_after_original_removed(self):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            probe, source, mkv = [directory / name for name in ("probe", "source.mp4", "result.mkv")]
            subprocess.run(["swiftc", "-parse-as-library",
                            *(str(ROOT / f"VoiceMatrix/{file}.swift") for file in
                              ("MP4SampleTable", "MatroskaWriter", "LocalMatroskaReader")),
                            str(ROOT / "probes/mkv-reader/main.swift"), "-o", str(probe)],
                           check=True, timeout=120)
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=25",
                            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "3",
                            "-c:v", "libx264", "-bf", "0", "-pix_fmt", "yuv420p", "-c:a", "aac",
                            "-use_editlist", "0", str(source)], check=True, timeout=60)
            output = subprocess.check_output([str(probe), str(source), str(mkv)], timeout=60)
            self.assertIn(b"WRITER_READER_H264_AAC_SHA_TIMELINE_OK", output)
            self.assertFalse(source.exists())
