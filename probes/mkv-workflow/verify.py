"""Independent packet, timing, pixel, and native PCM oracle for the saved clip."""
import array
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile


def floats(raw):
    samples = array.array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tests.test_local_matroska_derived import adts_payload_hashes


RATE, START, FRAMES = 44100, 88200, 441000
LIMIT = 3e-5


def command(*args):
    return subprocess.check_output([str(a) for a in args], timeout=90)


def probe(path, stream, *args):
    return json.loads(command("ffprobe", "-v", "error", "-select_streams", stream, *args,
                              "-of", "json", path))


def audio(path, codec, encoding):
    return command("ffmpeg", "-v", "error", "-i", path, "-map", "0:a:0",
                   "-c:a", codec, "-f", encoding, "-")


def video(path):
    frames = probe(path, "v:0", "-show_frames", "-show_entries",
                   "frame=best_effort_timestamp_time,width,height,pix_fmt")["frames"]
    timings = [Fraction(f["best_effort_timestamp_time"]) for f in frames]
    assert timings and timings[0] == 0 and all(a < b for a, b in zip(timings, timings[1:]))
    assert all((f["width"], f["height"], f["pix_fmt"]) == (160, 120, "yuv420p") for f in frames)
    pixels = command("ffmpeg", "-v", "error", "-i", path, "-map", "0:v:0",
                     "-fps_mode", "passthrough", "-pix_fmt", "yuv420p", "-f", "rawvideo", "-")
    assert len(pixels) == len(frames) * 160 * 120 * 3 // 2
    return timings, hashlib.sha256(pixels).hexdigest()


def metric(left, right, baseline=None):
    assert len(left) == len(right) and len(left) > 0
    assert baseline is None or len(baseline) == len(left)
    errors = (abs(l - r) for l, r in zip(left, right)) if baseline is None else (
        abs((l - b) - (r - b)) for l, r, b in zip(left, right, baseline))
    maximum = total = 0.0
    max_index = 0
    for i, difference in enumerate(errors):
        assert math.isfinite(difference)
        if difference > maximum:
            maximum, max_index = difference, i
        total += difference * difference
    return {"maximum": maximum, "rms": math.sqrt(total / len(left)),
            "maxFrameIndex": max_index, "frames": len(left)}


assert len(sys.argv) == 4, "Expected evidence directory, fixture manifest, and independent native probe"
evidence = Path(sys.argv[1])
fixture = json.loads(Path(sys.argv[2]).read_text())
receipt = json.loads((evidence / "result.json").read_text())
assert receipt["originalSHA256"] == fixture["mp4SHA256"]
assert receipt["originalAbsentDuringDeriveAndExtraction"] is True and receipt["sourceAndSentinelPreserved"] is True
assert (receipt["frames"], receipt["startSeconds"], receipt["sampleRate"]) == (441000, 2, 44100)
for key, name in (("mkvSHA256", "source.mkv"), ("derivedSHA256", "derived.mov"), ("clipSHA256", "clip.f32le")):
    assert hashlib.sha256((evidence / name).read_bytes()).hexdigest() == receipt[key]
assert len({receipt[k] for k in ("originalSHA256", "mkvSHA256", "derivedSHA256")}) == 3

committed_wav = (evidence / "committed-clip.wav").read_bytes()
committed_data = (evidence / "committed-clip-receipt.json").read_bytes()
committed = json.loads(committed_data)
assert hashlib.sha256(committed_wav).hexdigest() == receipt["committedWAVSHA256"] == committed["clipSHA256"]
assert hashlib.sha256(committed_data).hexdigest() == receipt["committedReceiptSHA256"]
assert (committed["requestedStart"], committed["requestedSeconds"], committed["actualStart"], committed["frames"]) == (2, 10, 2, 441000)
assert committed["sourceJobID"] == receipt["jobID"] and committed["sourceSHA256"] == receipt["derivedSHA256"]
assert committed["matroskaLineage"] == {
    "schemaVersion": 1, "jobID": receipt["jobID"], "attemptID": receipt["attemptID"],
    "acquisitionSHA256": receipt["originalSHA256"], "mkvSHA256": receipt["mkvSHA256"],
    "derivedSHA256": receipt["derivedSHA256"],
}
assert committed_wav[:4] == b"RIFF" and committed_wav[8:12] == b"WAVE"
assert committed_wav[44:] == (evidence / "clip.f32le").read_bytes()

mkv, mov = evidence / "source.mkv", evidence / "derived.mov"
mkv_video, mov_video = video(mkv), video(mov)
assert mkv_video == mov_video, "Video timestamps or decoded pixels differ"
for path, codec, time_base in ((mkv, "aac", "1/1000"), (mov, "pcm_s16le", "1/44100")):
    assert probe(path, "a", "-show_entries",
                 "stream=codec_name,sample_rate,channels,start_pts,time_base")["streams"] == [
                     {"codec_name": codec, "sample_rate": str(RATE), "channels": 1,
                      "start_pts": 0, "time_base": time_base}]
packets = probe(mkv, "a:0", "-show_packets", "-show_data_hash", "sha256")["packets"]
assert packets and Fraction(packets[0]["pts_time"]) == 0
for i, packet in enumerate(packets):
    assert packet["pts"] == packet["dts"]
    assert abs(Fraction(packet["pts_time"]) - Fraction(i * 1024, RATE)) <= Fraction(1, 1000)
trims = [(i, e) for i, p in enumerate(packets) for e in p.get("side_data_list", ())]
assert len(trims) == 1 and trims[0][0] == len(packets) - 1
tail = trims[0][1]
assert tail["side_data_type"] == "Skip Samples" and tail["skip_samples"] == 0
discard = tail["discard_padding"]
assert 0 < discard < 1024
raw_count = len(packets) * 1024
admitted = raw_count - discard
assert START + FRAMES <= admitted
for i, packet in enumerate(packets):
    expected_duration = Fraction(1024 - (discard if i == len(packets) - 1 else 0), RATE)
    assert abs(Fraction(packet["duration_time"]) - expected_duration) <= Fraction(1, 1000)
cursor = 0
mov_packets = probe(mov, "a:0", "-show_packets", "-show_entries",
                    "packet=pts,dts,duration,size")["packets"]
for packet in mov_packets:
    assert packet["pts"] == packet["dts"] == cursor
    assert packet["duration"] > 0 and int(packet["size"]) == packet["duration"] * 2
    cursor += packet["duration"]
assert cursor == admitted, "MOV audio timeline does not cover admitted frames exactly"

ff_mkv = audio(mkv, "pcm_f32le", "f32le")
mov_pcm = audio(mov, "copy", "s16le")
with tempfile.TemporaryDirectory() as tmp:
    adts, pcm = (Path(tmp) / name for name in ("oracle.aac", "oracle.pcm"))
    adts.write_bytes(audio(mkv, "copy", "adts"))
    assert [(p["size"], p["data_hash"]) for p in packets] == adts_payload_hashes(adts.read_bytes(), RATE)
    ff_adts = audio(adts, "pcm_f32le", "f32le")
    assert len(ff_mkv) == admitted * 4 and len(ff_adts) == raw_count * 4
    assert ff_mkv == ff_adts[:admitted * 4], "Independent FFmpeg wrapper changed admitted PCM"
    command(Path(sys.argv[3]).resolve(), "adts-pcm", adts, pcm, RATE, raw_count)
    native_pcm = pcm.read_bytes()
assert len(mov_pcm) == admitted * 2 and len(native_pcm) == raw_count * 2
native_pcm = native_pcm[:admitted * 2]


def pcm16(raw):
    samples = array.array("h")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return [sample / 32768 for sample in samples]


independent_native = pcm16(native_pcm)
derived = pcm16(mov_pcm)
expected = floats(ff_mkv)
clip_bytes = (evidence / "clip.f32le").read_bytes()
clip = floats(clip_bytes)
assert len(clip) == 2 * FRAMES and max(map(abs, expected[START:START + FRAMES])) > 0.01
window = slice(START, START + FRAMES)
# FFmpeg and Apple disagree on some AAC bins. The reported raw difference is not
# transformation error: cancel only the independently measured decoder baseline,
# then still require bit identity and check the original limit over every sample.
raw_error = metric(derived, expected)
raw_clip = [metric(clip[channel::2], expected[window]) for channel in (0, 1)]
full_residual = metric(derived, independent_native, expected)
channel_residuals = [metric(clip[channel::2], independent_native[window], expected[window])
                     for channel in (0, 1)]
expected_clip = array.array("f", (value for sample in independent_native[window]
                                  for value in (sample, sample)))
if sys.byteorder != "little":
    expected_clip.byteswap()
clip_equality = clip_bytes == expected_clip.tobytes()
report = {"frames": FRAMES, "startFrame": START, "sampleRate": RATE, "source": "verifiedMKV",
          "noMP4Fallback": True, "audioPackets": len(packets), "rawFrames": raw_count,
          "admittedFrames": admitted, "leadingSkipFrames": 0, "terminalDiscardFrames": discard,
          "allADTSAccessUnitHashesVerified": True, "allAudioPacketTimingsVerified": True, "ffmpegMKVVsADTSBitExact": True,
          "decodedVideoFrames": len(mkv_video[0]), "decodedVideoSHA256": mkv_video[1],
          "videoTimingAndPixelsBitExact": True, "rawFFmpegVsMOV": raw_error,
          "rawFFmpegVsClipByChannel": raw_clip, "legacyRawCrossDecoderLimitPassed":
              all(m["maximum"] < LIMIT for m in raw_clip),
          "transformationResidualLimit": LIMIT, "fullMOVResidual": full_residual,
          "clipResidualByChannel": channel_residuals, "nativeADTSVsMOVBitExact": native_pcm == mov_pcm,
          "nativeADTSVsClipBitExact": clip_equality}
print(json.dumps(report, sort_keys=True), flush=True)
assert all(m["maximum"] < LIMIT for m in [full_residual, *channel_residuals]), "Transformation residual exceeds limit"
assert report["nativeADTSVsMOVBitExact"] and clip_equality, "Independent native reference differs"
