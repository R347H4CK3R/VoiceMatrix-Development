"""Fail closed on metadata-only iOS synthesis evidence. XCTest examines the actual audio."""
import json
from pathlib import Path
import re
import sys

report = json.loads(Path(sys.argv[1]).read_text())
assert report["metadataOnly"] is True
assert report["priorVoicePreserved"] is True
assert report["identityVerified"] is report["physicalDeviceVerified"] is report["liveURLVerified"] is False
assert report["phaseOnePID"] > 0 and report["phaseTwoPID"] > 0
assert report["phaseOnePID"] != report["phaseTwoPID"]
assert report["distinctFixtureTurns"] == 2
assert report["mkvSHA256"] != report["derivedSHA256"]
generated = report["generated"]
assert len(generated) == len({row["voiceID"] for row in generated}) == 2
hashes = [report["originalSHA256"], report["mkvSHA256"], report["derivedSHA256"]]
for row in generated:
    assert 0 <= row["wordErrorRate"] <= 0.1
    hashes.extend(row[key] for key in ("referenceSHA256", "manifestSHA256", "clipSHA256", "previewSHA256", "speechSHA256"))
assert len(set(hashes)) == len(hashes) and all(re.fullmatch(r"[0-9a-f]{64}", value) for value in hashes)
print(json.dumps(dict(realF5Profiles=2, processRelaunchVerified=True, metadataOnly=True,
                      physicalDeviceVerified=False, identityVerified=False, liveURLVerified=False)))
