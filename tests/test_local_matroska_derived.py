"""Portable source contracts; decoded parity is separately gated on macOS."""
import hashlib
import json
import math
import platform
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class DerivedSourcePolicy(unittest.TestCase):
    def test_production_adapter_exists(self):
        self.assertTrue((ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").is_file(),
                        "Missing verified MKV-only adapter")

    @unittest.skipUnless((ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").is_file(), "adapter absent")
    def test_no_original_container_or_external_process_dependency(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        for blocked in ("MP4SampleTable", "LocalMKVExport", "Process(", "ffmpeg", "sourceMP4"):
            self.assertNotIn(blocked, source)
        self.assertIn("LocalMatroskaReader(url: sourceMKV, expectedSHA256: expectedSHA256", source)


# The reference used by both fixture rates is generated independently by
# ffmpeg from the exact verified MKV, after the sole original has been removed.
@unittest.skipUnless(platform.system() == "Darwin" and all(shutil.which(p) for p in ("swiftc", "ffmpeg", "ffprobe")),
                     "native derivation requires macOS AVFoundation/CryptoKit and ffmpeg")
class DerivedNativeParity(unittest.TestCase):
    def run_tool(self, *args):
        return subprocess.check_output([str(arg) for arg in args], timeout=240)

    def test_trimmed_aac_and_video_from_verified_mkv_without_original(self):
        with tempfile.TemporaryDirectory() as scratch:
            d = Path(scratch)
            probe = d / "probe"
            self.run_tool("swiftc", "-parse-as-library",
                          *(ROOT / "VoiceMatrix" / (name + ".swift") for name in (
                              "MP4SampleTable", "MatroskaWriter", "LocalMKVExport",
                              "LocalMatroskaReader", "LocalMatroskaDerivedMedia")),
                          ROOT / "probes/mkv-derived/main.swift", "-o", probe)
            for rate in (44100, 48000):
                with self.subTest(rate=rate):
                    media = d / str(rate)
                    media.mkdir()
                    self.check_fixture(probe, media, rate)

    def check_fixture(self, probe, d, rate):
        src, mkv, mov = (d / name for name in ("original.mp4", "verified.mkv", "derived.mov"))
        before_frames, after_frames, native_pcm = (d / name for name in ("before.json", "after.json", "native.pcm"))
        # 30000/1001 video timestamps exercise alternating 33/34 ms.
        # Nonstationary audio cues at both boundaries make any one-frame
        # priming/removal, shifted output, or padded epilogue observable.
        tone = (f"aevalsrc=0.21*sin(2*PI*(280*t+37*t*t))"
                f"+0.11*sin(2*PI*997*t)*exp(-15*t)+"
                f"0.18*sin(2*PI*1321*t)*exp(25*(t-3.031)):s={rate}")
        self.run_tool("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=160x120:rate=30000/1001",
                      "-f", "lavfi", "-i", tone, "-t", "3.031", "-c:v", "libx264", "-bf", "0",
                      "-pix_fmt", "yuv420p", "-c:a", "aac", "-use_editlist", "0", src)
        original_sha = hashlib.sha256(src.read_bytes()).hexdigest()
        self.run_tool(probe, "video", src, before_frames)
        self.run_tool(probe, "export", src, mkv)
        self.assertEqual(hashlib.sha256(src.read_bytes()).hexdigest(), original_sha)
        original_bytes = src.read_bytes()
        src.unlink()
        self.assertFalse(src.exists())
        digest = hashlib.sha256(mkv.read_bytes()).hexdigest()
        oracle = self.run_tool("ffmpeg", "-v", "error", "-i", mkv, "-map", "0:a:0", "-f", "s16le", "-")
        packet_data = json.loads(self.run_tool("ffprobe", "-v", "error", "-select_streams", "v:0",
                                              "-show_packets", "-of", "json", mkv))
        # ffprobe reads the 1 ms MKV time base; no production table inference.
        oracle_ms = [int(p["pts"]) for p in packet_data["packets"]]
        self.assertGreater(len(set(b-a for a, b in zip(oracle_ms, oracle_ms[1:]))), 1)
        receipt = json.loads(self.run_tool(probe, "derive", mkv, digest, mov))
        self.assertFalse(src.exists())
        self.assertEqual(hashlib.sha256(mkv.read_bytes()).hexdigest(), digest)
        self.assertEqual(receipt["mkvSHA256"], digest)
        self.assertEqual(receipt["movSHA256"], hashlib.sha256(mov.read_bytes()).hexdigest())
        self.assertEqual(receipt["movBytes"], mov.stat().st_size)
        self.assertGreater(receipt["discardFrames"], 0)
        self.assertEqual(receipt["audioSampleRate"], rate)
        self.assertEqual(receipt["audioChannels"], 1)
        self.assertEqual(receipt["audioFrames"], len(oracle) // 2)
        self.assertEqual(receipt["audioPackets"] * 1024 - receipt["discardFrames"], len(oracle) // 2)
        self.run_tool(probe, "pcm", mov, native_pcm)
        pcm = native_pcm.read_bytes()
        self.assertEqual(len(pcm), len(oracle))
        delta = [abs(a-b) for (a,), (b,) in zip(struct.iter_unpack("<h", pcm), struct.iter_unpack("<h", oracle))]
        # Native/FFmpeg inverse-transform rounding differences, never a
        # duration/offset waiver. Inspect entire PCM as well as each edge.
        for comparison in (delta, delta[:1024], delta[-1024:]):
            self.assertLessEqual(max(comparison), 16)
            self.assertLessEqual(math.sqrt(sum(x*x for x in comparison) / len(comparison)), 2)
        self.run_tool(probe, "video", mov, after_frames)
        before, after = (json.loads(file.read_bytes()) for file in (before_frames, after_frames))
        self.assertEqual([f["sha256"] for f in after], [f["sha256"] for f in before])
        self.assertEqual([f["ptsMS"] for f in after], oracle_ms)
        self.assertEqual(len(after), receipt["videoFrames"])

        race = d / "existing.mov"
        race.write_bytes(b"prior result")
        canceled = d / "cancel.mov"
        status = subprocess.run([probe, "cancel", mkv, digest, canceled], capture_output=True, timeout=240)
        self.assertEqual(status.returncode, 2, status.stderr)
        self.assertFalse(canceled.exists())
        tiny = d / "tiny.mov"
        status = subprocess.run([probe, "derive", mkv, digest, tiny, "100"],
                                capture_output=True, timeout=240)
        self.assertNotEqual(status.returncode, 0)
        self.assertFalse(tiny.exists())
        status = subprocess.run([probe, "derive", mkv, digest, race], capture_output=True, timeout=240)
        self.assertNotEqual(status.returncode, 0)
        self.assertEqual(race.read_bytes(), b"prior result")

        # Even if another readable MP4 exists, accept no companion fallback.
        src.write_bytes(original_bytes)
        broken = d / "broken.mkv"
        bad = bytearray(mkv.read_bytes())
        bad[-1] ^= 0x01  # late cue evidence failure, with valid file identity
        broken.write_bytes(bad)
        bad_dest = d / "bad.mov"
        status = subprocess.run([probe, "derive", broken, hashlib.sha256(bad).hexdigest(), bad_dest],
                                capture_output=True, timeout=240)
        self.assertNotEqual(status.returncode, 0)
        self.assertFalse(bad_dest.exists())
        self.assertEqual(hashlib.sha256(src.read_bytes()).hexdigest(), original_sha)
        self.assertFalse(list(d.glob(".mkv-derived-*")))
