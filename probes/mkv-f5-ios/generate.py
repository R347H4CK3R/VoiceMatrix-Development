"""Create a test-only H.264/AAC fixture from exact attributed, nonoverlapping source recordings."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SOURCES = json.loads((ROOT / "probes/human-local-studio/sources.json").read_text())
PIN = {
    "2961-960-0003": ("1c7709259d871c7a36fe1f994f6f1bce0a3424c6f009002eb3defcd3f1a97040", 17.315),
    "4507-16021-0031": ("c76e682d374b296c709d2c1a9484e4c7176886cb6aab2cd99795d4d9925b7dfa", 14.31),
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

inputs, turns = [], []
start = 0.0
for identifier, (digest, duration) in PIN.items():
    source, = (row for row in SOURCES if row["id"] == identifier)
    audio = ROOT / "tests/fixtures/licensed-human-source" / f"{identifier}.flac"
    assert audio.is_file() and not audio.is_symlink()
    assert source["sourceSHA256"] == sha(audio) == digest and source["license"] == "CC-BY-4.0"
    assert source["referenceText"].strip()
    observed = float(subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(audio)],
        text=True, timeout=15))
    assert abs(observed - duration) < 0.00005
    inputs += ["-i", str(audio)]
    turns.append(dict(id=identifier, sha256=digest, start=start, end=round(start + duration, 6),
                      referenceText=source["referenceText"]))
    start = round(start + duration + 1.5, 6)
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
mp4 = out / "strict-f5-licensed.mp4"
subprocess.run(
    ["ffmpeg", "-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=s=160x120:r=25", *inputs,
     "-filter_complex",
     "[1:a]aresample=44100[a];anullsrc=r=44100:cl=mono,atrim=duration=1.5[gap];"
     "[2:a]aresample=44100[b];[a][gap][b]concat=n=3:v=0:a=1[voice]",
     "-map", "0:v:0", "-map", "[voice]", "-shortest", "-c:v", "libx264", "-bf", "0",
     "-pix_fmt", "yuv420p", "-c:a", "aac", "-ar", "44100", "-ac", "1", "-use_editlist", "0", str(mp4)],
    check=True, timeout=45)
assert 0 < mp4.stat().st_size <= 32_000_000
(out / "strict-f5-fixture.json").write_text(json.dumps(dict(
    schemaVersion=1, mp4SHA256=sha(mp4), turns=turns, license="CC-BY-4.0",
    attribution="LibriSpeech (Panayotov, Chen, Povey, and Khudanpur), OpenSLR 12",
    source="https://www.openslr.org/12", syntheticVideo=True, identityVerified=False), sort_keys=True))
