"""Independent ffmpeg decode oracle for the native exact-frame selection."""
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys


def floats(raw):
    samples = array.array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def mono(path):
    return floats(subprocess.check_output(["ffmpeg", "-v", "error", "-i", str(path), "-map", "0:a:0",
                                          "-ar", "44100", "-ac", "1", "-f", "f32le", "-"]))


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

expected = mono(evidence / "source.mkv")[88200:529200]
derived = mono(evidence / "derived.mov")[88200:529200]
native = floats((evidence / "clip.f32le").read_bytes())
assert len(native) == 882000 and len(expected) == len(derived) == 441000
assert all(math.isfinite(value) for seq in (native, expected, derived) for value in seq)
assert max(map(abs, expected)) > 0.01


def error(reference):
    return max(max(abs(native[2*i] - x), abs(native[2*i+1] - x)) for i, x in enumerate(reference))


mkv_error, mov_error = error(expected), error(derived)
assert mkv_error < 3e-5, f"MKV parity failed: max {mkv_error}"
assert mov_error < 3e-5, f"derived MOV parity failed: max {mov_error}"
print(json.dumps({"frames": 441000, "startFrame": 88200, "maximumMKVError": mkv_error,
                  "maximumMOVError": mov_error, "source": "verifiedMKV", "noMP4Fallback": True}, sort_keys=True))
