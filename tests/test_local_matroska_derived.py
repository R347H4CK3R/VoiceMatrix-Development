"""Portable source contracts; decoded parity is separately gated on macOS."""
import hashlib
import json
import math
import platform
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]



def pcm_error_evidence(actual, expected):
    """Return packet-indexed error evidence without changing the parity gate."""
    if not actual or len(actual) != len(expected) or len(actual) % 2:
        raise ValueError("PCM diagnostic requires equal nonempty Int16 buffers")
    pairs = list(zip(struct.iter_unpack("<h", actual), struct.iter_unpack("<h", expected)))
    result = {}
    for name, start, end in (("all", 0, len(pairs)), ("first", 0, min(len(pairs), 1024)),
                             ("last", max(0, len(pairs) - 1024), len(pairs))):
        differences = [abs(a - b) for (a,), (b,) in pairs[start:end]]
        maximum = max(differences)
        index = start + differences.index(maximum)
        (a,), (b,) = pairs[index]
        result[name] = {"maximum": maximum, "rms": math.sqrt(sum(d*d for d in differences) / len(differences)),
                        "over16": sum(d > 16 for d in differences), "index": index,
                        "aacPacket": index // 1024, "packetOffset": index % 1024,
                        "actual": a, "expected": b}
    return result


def adts_payload_hashes(raw, rate):
    """Observe only baseline AAC-LC mono ADTS transport frames."""
    index = {44100: 4, 48000: 3}[rate]
    cursor, packets = 0, []
    while cursor < len(raw):
        h = raw[cursor:cursor+7]
        if (len(h) != 7 or h[:2] != b"\xff\xf1" or h[2] >> 6 != 1
                or ((h[2] >> 2) & 15) != index or (((h[2] & 1) << 2) | (h[3] >> 6)) != 1
                or h[6] & 3):
            raise ValueError("unsupported ADTS fixture transport")
        length = ((h[3] & 3) << 11) | (h[4] << 3) | (h[5] >> 5)
        if length <= 7 or cursor + length > len(raw):
            raise ValueError("incomplete ADTS fixture access unit")
        payload = raw[cursor+7:cursor+length]
        packets.append((str(len(payload)), "SHA256:" + hashlib.sha256(payload).hexdigest()))
        cursor += length
    if not packets:
        raise ValueError("ADTS fixture contains no access units")
    return packets


class ADTSPacketEvidence(unittest.TestCase):
    @staticmethod
    def frame(data):
        length = len(data) + 7
        return bytes((0xff, 0xf1, 0x4c, 0x40 | (length >> 11), (length >> 3) & 0xff,
                      ((length & 7) << 5) | 0x1f, 0xfc)) + data

    def test_hashes_raw_access_units_without_transport_headers(self):
        packets = (b"abc", bytes(range(100)))
        self.assertEqual(adts_payload_hashes(b"".join(map(self.frame, packets)), 48000),
                         [(str(len(p)), "SHA256:" + hashlib.sha256(p).hexdigest()) for p in packets])

    def test_rejects_truncation_unsupported_layout_and_changed_rate(self):
        frame = self.frame(b"abc")
        for invalid in (b"", frame[:-1], bytes([0]) + frame[1:],
                        frame[:1] + bytes([0xf0]) + frame[2:],
                        frame[:6] + bytes([0xfd]) + frame[7:]):
            with self.assertRaises(ValueError):
                adts_payload_hashes(invalid, 48000)
        with self.assertRaises(ValueError):
            adts_payload_hashes(frame, 44100)


class PCMErrorEvidence(unittest.TestCase):
    def test_distinguishes_access_unit_and_edges(self):
        values = [0] * 4096
        values[17], values[1029], values[4092] = -18, 23, -19
        report = pcm_error_evidence(struct.pack("<4096h", *values), bytes(len(values) * 2))
        self.assertEqual((report["all"]["index"], report["all"]["aacPacket"], report["all"]["packetOffset"]),
                         (1029, 1, 5))
        self.assertEqual((report["all"]["actual"], report["all"]["expected"], report["all"]["over16"]), (23, 0, 3))
        self.assertEqual((report["first"]["index"], report["last"]["index"]), (17, 4092))
        self.assertAlmostEqual(report["all"]["rms"], math.sqrt((18**2 + 23**2 + 19**2) / 4096))

    def test_rejects_unaligned_comparison(self):
        for actual, expected in ((b"", b""), (b"1", b"1"), (b"12", b"1234")):
            with self.assertRaises(ValueError):
                pcm_error_evidence(actual, expected)


def nv12_hashes(raw, width, height):
    """Hash packed Y/U/V bytes in the native probe's visible Y+UV row order."""
    if width <= 0 or height <= 0 or width % 2 or height % 2:
        raise ValueError("NV12 oracle requires positive even dimensions")
    luma = width * height
    chroma = luma // 4
    frame_size = luma + 2 * chroma
    if not raw or len(raw) % frame_size:
        raise ValueError("Missing or incomplete oracle video frame")
    hashes = []
    for offset in range(0, len(raw), frame_size):
        frame = memoryview(raw)[offset:offset + frame_size]
        uv = bytearray(2 * chroma)
        uv[0::2] = frame[luma:luma + chroma]
        uv[1::2] = frame[luma + chroma:]
        digest = hashlib.sha256(frame[:luma])
        digest.update(uv)
        hashes.append(digest.hexdigest())
    return hashes


class MKVPixelOraclePacking(unittest.TestCase):
    def test_hashes_canonical_nv12_with_ordered_interleaved_chroma(self):
        # 4×2 planar frame: eight luma bytes, two U bytes, two V bytes.
        planar = b"ABCDEFGH" + b"IJ" + b"KL"
        canonical = b"ABCDEFGHIKJL"
        alternate = planar[:-1] + b"M"
        self.assertEqual(nv12_hashes(planar + alternate, 4, 2), [
            hashlib.sha256(canonical).hexdigest(),
            hashlib.sha256(canonical[:-1] + b"M").hexdigest(),
        ])

    def test_rejects_truncated_or_misaligned_oracle(self):
        for raw, width, height in ((b"x" * 11, 4, 2), (b"", 4, 2), (b"x" * 12, 3, 2)):
            with self.subTest(width=width, count=len(raw)):
                with self.assertRaises(ValueError):
                    nv12_hashes(raw, width, height)


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


    def test_native_rejection_reports_only_timeline_and_writer_state(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        markers = ("phase=", "packetCount=", "appendedAudio=", "appendedVideo=",
                   "lastMKVPTS=", "writerStatus=", "audioReady=", "videoReady=",
                   "actualVideo=", "expectedVideo=", "actualAudio=", "expectedAudio=",
                   "audioSegmentMappings=")
        for marker in markers:
            with self.subTest(marker=marker):
                self.assertIn(marker, source)


    def test_stored_timing_is_exact_before_decoded_duration_can_be_absent(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        for marker in ("validateStoredVideoTiming", "observations == 1", "sample.samples == 0",
                       "sample.bytes == 0", "sample.pts == .zero", "sample.duration == .zero",
                       "sample.samples == 1", "sample.duration == expectedDuration",
                       "index == videoPTS.count", "outputSettings: nil", "!decodedDuration.isValid"):
            self.assertIn(marker, source)
        self.assertLess(source.index("try validateStoredVideoTiming"), source.index("let decoded ="))

    def test_rejected_video_marker_reports_native_metadata(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        for marker in ("storedObservation=", "sampleCount=", "payloadBytes=",
                       "hasImage=", "observedTiming=", "observedDTS=", "emptyMedia=",
                       "endsPreviousSampleDuration=", "expectedTrackEnd="):
            self.assertIn(marker, source)

    def test_terminal_no_media_sequence_requires_exact_end_and_immediate_eof(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        for marker in ("isTerminalNoMedia", "!pts.isValid", "!dts.isValid", 'emptyMedia == "absent"',
                       'endsPreviousSampleDuration == "absent"', "second.isTerminalNoMedia",
                       "boundary.isTerminalEnd(at: end)", "nextSample() == nil",
                       "storedReader.status == .completed"):
            self.assertIn(marker, source)
        self.assertIn("index == videoPTS.count, sample.isTerminalNoMedia", source)

    def test_verified_packet_tape_pumps_each_ready_input_independently(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        for marker in ("IndexedPacket", "spooling-mkv-packets", "packetIndexLimit",
                       "if !audioFinished, audio.isReadyForMoreMediaData",
                       "if !videoFinished, video.isReadyForMoreMediaData",
                       "if !progressed"):
            self.assertIn(marker, source)
        self.assertLess(source.index("try reader.forEachPacket"), source.index("writer.startWriting()"))
        self.assertNotIn("while !input.isReadyForMoreMediaData", source)
        probe = (ROOT / "probes/mkv-derived/main.swift").read_text()
        self.assertIn("appendProgress:", probe)
        self.assertIn('"cancel-pump"', probe)

    def test_pcm_is_native_decoded_from_verified_access_units_before_writer(self):
        source = (ROOT / "VoiceMatrix/LocalMatroskaDerivedMedia.swift").read_text()
        for marker in ("AVAudioConverter(from:", "AVAudioCompressedBuffer(", ".endOfStream",
                       "decoderProducedFrames == expectedDecoderFrames", "validAudioFrames",
                       "audioPCMFormat.formatDescription", "decodeProgress"):
            self.assertIn(marker, source)
        self.assertLess(source.index("try reader.forEachPacket"), source.index("try stagePCM("))
        self.assertLess(source.index("try stagePCM("), source.index("writer.startWriting()"))
        self.assertNotIn("kCMSampleBufferAttachmentKey_TrimDurationAtStart", source)
        self.assertNotIn("kCMSampleBufferAttachmentKey_TrimDurationAtEnd", source)


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
            self.run_tool(probe, "stored-policy")
            for rate in (44100, 48000):
                with self.subTest(rate=rate):
                    media = d / str(rate)
                    media.mkdir()
                    self.check_fixture(probe, media, rate)

    def compare_direct_native_aac(self, probe, mkv, folder, receipt, actual, expected):
        wrapped, direct_path = folder / "direct-aac.aac", folder / "direct-native.pcm"
        def diagnostic_tool(*args):
            return subprocess.check_output([str(arg) for arg in args], timeout=15)

        diagnostic_tool("ffmpeg", "-v", "error", "-i", mkv, "-map", "0:a:0", "-c:a", "copy",
                      "-f", "adts", wrapped)
        def compressed(path):
            data = json.loads(diagnostic_tool("ffprobe", "-v", "error", "-select_streams", "a:0",
                                            "-show_packets", "-show_data_hash", "sha256", "-of", "json", path))
            return [(p["size"], p["data_hash"]) for p in data["packets"]]
        source_packets = compressed(mkv)
        wrapper_packets = adts_payload_hashes(wrapped.read_bytes(), receipt["audioSampleRate"])
        if source_packets != wrapper_packets or len(source_packets) != receipt["audioPackets"]:
            raise ValueError("diagnostic AAC access units were not copied exactly")
        diagnostic_tool(probe, "adts-pcm", wrapped, direct_path, receipt["audioSampleRate"], receipt["audioPackets"] * 1024)
        native = direct_path.read_bytes()
        encoded_bytes = receipt["audioPackets"] * 1024 * 2
        print("PCM_DIRECT_NATIVE_LENGTH", json.dumps({"rate": receipt["audioSampleRate"],
              "directBytes": len(native), "fullBytes": encoded_bytes, "validBytes": len(actual),
              "verifiedPackets": len(source_packets), "discardFrames": receipt["discardFrames"]},
              sort_keys=True), flush=True)
        # Without full decoded frame count, the independent container may impose
        # its own trimming and cannot establish the exact decoder baseline.
        if len(native) == encoded_bytes:
            raw = native[:len(actual)]
            print("PCM_DIRECT_NATIVE", receipt["audioSampleRate"],
                  json.dumps({"derivedVsNative": pcm_error_evidence(actual, raw),
                              "nativeVsFFmpeg": pcm_error_evidence(raw, expected)}, sort_keys=True), flush=True)

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
        oracle_video = self.run_tool("ffmpeg", "-v", "error", "-i", mkv, "-map", "0:v:0",
                                     "-fps_mode", "passthrough", "-pix_fmt", "yuv420p",
                                     "-c:v", "rawvideo", "-threads:v", "1", "-f", "rawvideo", "-")
        oracle_pixel_hashes = nv12_hashes(oracle_video, 160, 120)
        self.assertEqual(len(oracle_pixel_hashes), len(oracle_ms))
        receipt = json.loads(self.run_tool(probe, "derive", mkv, digest, mov))
        self.assertFalse(src.exists())
        self.assertEqual(hashlib.sha256(mkv.read_bytes()).hexdigest(), digest)
        self.assertEqual(receipt["mkvSHA256"], digest)
        self.assertEqual(receipt["movSHA256"], hashlib.sha256(mov.read_bytes()).hexdigest())
        self.assertEqual(receipt["movBytes"], mov.stat().st_size)
        self.assertGreater(receipt["discardFrames"], 0)
        self.assertEqual(receipt["audioSampleRate"], rate)
        self.assertEqual(receipt["audioChannels"], 1)
        derived_formats = json.loads(self.run_tool("ffprobe", "-v", "error", "-show_streams",
                                                   "-of", "json", mov))
        self.assertEqual({s["codec_type"]: s["codec_name"] for s in derived_formats["streams"]},
                         {"video": "h264", "audio": "pcm_s16le"})
        self.assertEqual(receipt["audioFrames"], len(oracle) // 2)
        self.assertEqual(receipt["audioPackets"] * 1024 - receipt["discardFrames"], len(oracle) // 2)
        self.run_tool(probe, "pcm", mov, native_pcm)
        pcm = native_pcm.read_bytes()
        self.assertEqual(len(pcm), len(oracle))
        print("PCM_CROSS_DECODER", rate, json.dumps(pcm_error_evidence(pcm, oracle), sort_keys=True), flush=True)
        # Diagnostic only: copy, do not decode or re-encode, the independently demuxed
        # AAC samples into ADTS (no QuickTime edit list or packet table). Do not use this measurement
        # to waive either the existing FFmpeg bound or any of the other assertions.
        try:
            self.compare_direct_native_aac(probe, mkv, d, receipt, pcm, oracle)
        except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError) as exc:
            print("PCM_DIRECT_NATIVE_UNAVAILABLE", rate, str(exc), file=sys.stderr, flush=True)
        delta = [abs(a-b) for (a,), (b,) in zip(struct.iter_unpack("<h", pcm), struct.iter_unpack("<h", oracle))]
        # Native/FFmpeg inverse-transform rounding differences, never a
        # duration/offset waiver. Inspect entire PCM as well as each edge.
        for comparison in (delta, delta[:1024], delta[-1024:]):
            self.assertLessEqual(max(comparison), 16)
            self.assertLessEqual(math.sqrt(sum(x*x for x in comparison) / len(comparison)), 2)
        self.run_tool(probe, "video", mov, after_frames)
        before, after = (json.loads(file.read_bytes()) for file in (before_frames, after_frames))
        self.assertEqual([f["sha256"] for f in after], [f["sha256"] for f in before])
        self.assertEqual([f["sha256"] for f in after], oracle_pixel_hashes)
        self.assertEqual([f["ptsMS"] for f in after], oracle_ms)
        self.assertEqual(len(after), receipt["videoFrames"])

        race = d / "existing.mov"
        race.write_bytes(b"prior result")
        canceled = d / "cancel.mov"
        status = subprocess.run([probe, "cancel", mkv, digest, canceled], capture_output=True, timeout=240)
        self.assertEqual(status.returncode, 2, status.stderr)
        self.assertFalse(canceled.exists())
        decode_canceled = d / "decode-cancel.mov"
        status = subprocess.run([probe, "cancel-decode", mkv, digest, decode_canceled],
                                capture_output=True, timeout=240)
        self.assertEqual(status.returncode, 2, status.stderr)
        self.assertFalse(decode_canceled.exists())
        pump_canceled = d / "pump-cancel.mov"
        status = subprocess.run([probe, "cancel-pump", mkv, digest, pump_canceled],
                                capture_output=True, timeout=240)
        self.assertEqual(status.returncode, 2, status.stderr)
        self.assertFalse(pump_canceled.exists())
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
