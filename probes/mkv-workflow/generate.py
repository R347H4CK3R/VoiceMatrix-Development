"""Build and attest the licensed speech fixture; synthetic imagery is not identity evidence."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

source = Path("tests/fixtures/licensed-human-source/2961-960-0003.flac")
source_sha = "1c7709259d871c7a36fe1f994f6f1bce0a3424c6f009002eb3defcd3f1a97040"
assert hashlib.sha256(source.read_bytes()).hexdigest() == source_sha
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
mp4 = out / "strict-mkv-licensed.mp4"
subprocess.run(["ffmpeg", "-v", "error", "-n", "-f", "lavfi", "-i", "testsrc2=s=160x120:r=25",
                "-i", str(source), "-t", "17.315", "-map", "0:v:0", "-map", "1:a:0",
                "-c:v", "libx264", "-bf", "0", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-ar", "44100", "-ac", "1", "-use_editlist", "0", str(mp4)], check=True)
(out / "strict-mkv-fixture.json").write_text(json.dumps({
    "source": str(source), "sourceSHA256": source_sha, "license": "CC-BY-4.0",
    "provenance": "probes/human-local-studio/sources.json", "syntheticVideo": True,
    "mp4SHA256": hashlib.sha256(mp4.read_bytes()).hexdigest(),
}, sort_keys=True))
