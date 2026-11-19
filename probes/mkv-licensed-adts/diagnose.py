"""Re-audit one exact failed clip artifact; no production code or release criterion changes."""
import array
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tests.test_local_matroska_derived import adts_payload_hashes

ARCHIVE = "e64b90d15c187070d6b184c5ee18173b2e84c764e491c3417c9778ae25f60a8b"
SOURCE = "a024129e51787497b41ffb1824be033fdfe38423"
TREE = "1e7f78716ca196e2a2c1682fe3a54d8cab97c419"
ARTIFACT = 14514418920
RATE = 44100
START = 88200
FRAMES = 441000
PACKETS = 747
DISCARD = 312
INPUTS = {
    "source.mkv": "mkvSHA256",
    "derived.mov": "derivedSHA256",
    "clip.f32le": "clipSHA256",
    "committed-clip.wav": "committedWAVSHA256",
    "committed-clip-receipt.json": "committedReceiptSHA256",
}
PREFIX = "strict-mkv-native-evidence/"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def command(*args):
    return subprocess.check_output([str(a) for a in args], timeout=60)


def samples(kind, raw):
    values = array.array(kind)
    values.frombytes(raw)
    if sys.byteorder != "little":
        values.byteswap()
    return values


def floats(path):
    return command("ffmpeg", "-v", "error", "-i", path, "-map", "0:a:0",
                   "-ac", 1, "-ar", RATE, "-f", "f32le", "-")


def metric(left, right):
    assert left and len(left) == len(right)
    differences = [abs(a - b) for a, b in zip(left, right)]
    index = max(range(len(differences)), key=differences.__getitem__)
    return {"maximum": differences[index],
            "rms": math.sqrt(math.fsum(d*d for d in differences) / len(differences)),
            "index": index, "samples": len(differences)}


def inspect_archive(path):
    archive = path.read_bytes()
    assert digest(archive) == ARCHIVE and len(archive) == 4685758
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        assert z.read("native-mkv-stage-source.txt").decode().strip() == SOURCE
        assert z.read("native-mkv-stage-tree.txt").decode().strip() == TREE
        proof = json.loads(z.read(PREFIX + "result.json"))
        fixture = json.loads(z.read(".strict-mkv-fixture/strict-mkv-fixture.json"))
        data = {name: z.read(PREFIX + name) for name in INPUTS}
    for name, field in INPUTS.items():
        assert digest(data[name]) == proof[field]
    assert fixture["mp4SHA256"] == proof["originalSHA256"]
    assert proof["originalAbsentDuringDeriveAndExtraction"] and proof["sourceAndSentinelPreserved"]
    assert (proof["sampleRate"], proof["startSeconds"], proof["frames"]) == (RATE, START/RATE, FRAMES)
    receipt = json.loads(data["committed-clip-receipt.json"])
    assert receipt["clipSHA256"] == proof["committedWAVSHA256"]
    assert (receipt["requestedStart"], receipt["requestedSeconds"], receipt["actualStart"], receipt["frames"]) == (2, 10, 2, FRAMES)
    assert receipt["sourceJobID"] == proof["jobID"] and receipt["sourceSHA256"] == proof["derivedSHA256"]
    assert receipt["matroskaLineage"] == {
        "schemaVersion": 1, "jobID": proof["jobID"], "attemptID": proof["attemptID"],
        "acquisitionSHA256": proof["originalSHA256"], "mkvSHA256": proof["mkvSHA256"],
        "derivedSHA256": proof["derivedSHA256"],
    }
    wav = data["committed-clip.wav"]
    assert wav[:4] == b"RIFF" and wav[8:12] == b"WAVE"
    assert wav[44:] == data["clip.f32le"]
    return proof, data


def diagnose(archive, native_probe=None):
    proof, data = inspect_archive(archive)
    with tempfile.TemporaryDirectory() as td:
        folder = Path(td)
        mkv, mov, adts = (folder / name for name in ("source.mkv", "derived.mov", "source.aac"))
        mkv.write_bytes(data["source.mkv"])
        mov.write_bytes(data["derived.mov"])
        command("ffmpeg", "-v", "error", "-n", "-i", mkv, "-map", "0:a:0", "-c:a", "copy", "-f", "adts", adts)
        packet_data = json.loads(command("ffprobe", "-v", "error", "-select_streams", "a:0",
                                         "-show_packets", "-show_data_hash", "sha256", "-of", "json", mkv))
        packets = packet_data["packets"]
        assert len(packets) == PACKETS
        spans = [(p["size"], p["data_hash"]) for p in packets]
        assert spans == adts_payload_hashes(adts.read_bytes(), RATE)
        flags = [(i, e) for i, p in enumerate(packets) for e in p.get("side_data_list", ())]
        assert len(flags) == 1 and flags[0][0] == PACKETS - 1
        side = flags[0][1]
        assert side["side_data_type"] == "Skip Samples" and side["discard_padding"] == DISCARD and side["skip_samples"] == 0
        full, admitted = PACKETS * 1024, PACKETS * 1024 - DISCARD
        ff_mkv = floats(mkv)
        ff_adts = floats(adts)
        mov_s16 = command("ffmpeg", "-v", "error", "-i", mov, "-map", "0:a:0", "-c:a", "copy", "-f", "s16le", "-")
        assert len(ff_mkv) == admitted * 4 and len(ff_adts) == full * 4
        assert ff_mkv == ff_adts[:admitted * 4] and len(mov_s16) == admitted * 2
        clip = samples("f", data["clip.f32le"])
        assert len(clip) == 2 * FRAMES and clip[::2] == clip[1::2]
        saved = clip[::2]
        mov_pcm = samples("h", mov_s16)
        aligned = [value / 32768 for value in mov_pcm[START:START + FRAMES]]
        assert list(saved) == aligned, "Saved clip and lossless MOV window differ."
        ffmpeg_pcm = samples("f", ff_mkv)
        clip_cross = metric(saved, ffmpeg_pcm[START:START+FRAMES])
        report = {
            "diagnosticOnly": True, "sourceArchiveSHA256": ARCHIVE, "sourceArtifactID": ARTIFACT,
            "exactSource": SOURCE, "sourceTree": TREE, "audioPackets": PACKETS,
            "adtsPayloadHashesVerified": True, "originalSHA256": proof["originalSHA256"],
            "mkvSHA256": proof["mkvSHA256"], "derivedSHA256": proof["derivedSHA256"],
            "clipSHA256": proof["committedWAVSHA256"], "committedReceiptSHA256": proof["committedReceiptSHA256"],
            "rawFrames": full, "admittedFrames": admitted, "terminalDiscardFrames": DISCARD,
            "leadingSkipFrames": 0, "clipStartFrame": START, "clipFrames": FRAMES,
            "mkvVsADTSFFmpegExactOverAdmittedFrames": True, "movVsSavedClipBitExact": True,
            "rawCrossDecoderClip": clip_cross, "legacyCrossDecoderMaxLimit": 3e-5,
            "legacyCrossDecoderLimitPassed": clip_cross["maximum"] < 3e-5,
            "fullRawCrossDecoder": metric([x / 32768 for x in mov_pcm], ffmpeg_pcm),
            "independentNativeADTSPerformed": native_probe is not None,
        }
        if native_probe is None:
            return report
        native_path = folder / "direct-native.pcm"
        command(native_probe, "adts-pcm", adts, native_path, RATE, full)
        native = native_path.read_bytes()
        assert len(native) == full * 2
        native = native[:admitted * 2]
        native_pcm = samples("h", native)
        report.update({
            "nativeADTSVsMOVBitExact": native == mov_s16,
            "nativeADTSVsSavedClipBitExact": list(saved) == [x / 32768 for x in native_pcm[START:START+FRAMES]],
            "nativeADTSVsMOVInt16": metric(native_pcm, mov_pcm),
            "nativeADTSVsFFmpegFull": metric([x / 32768 for x in native_pcm], ffmpeg_pcm),
        })
        return report


if __name__ == "__main__":
    assert len(sys.argv) in (2, 3)
    print(json.dumps(diagnose(Path(sys.argv[1]), *sys.argv[2:]), sort_keys=True))
