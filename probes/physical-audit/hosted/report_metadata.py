"""Print an exact, narrow CI evidence summary; never echo other fields or files."""
import json
from pathlib import Path
import re
import sys


def summary(data, source):
    sha = re.compile(r"^[a-f0-9]{64}$")
    runtime = "42da8f3ed18ca1c0f1462032db5dc05ce77362a1"
    if (not re.fullmatch("[a-f0-9]{40}", source) or data.get("auditSourceRevision") != source
            or data.get("exactRuntime") != runtime or data.get("auditBundleID") != "com.voicematrix.physicalaudit" or data.get("baselinePreserved") is not True
            or data.get("published") is not False or data.get("physicalIPhoneVerified") is not False
            or data.get("signedBundleIsolationVerified") is not False
            or data.get("python") != {"native": 69, "wheels": 3}):
        raise ValueError("Native archive proof did not validate")
    fields = ("graphSHA256", "xcodegenSHA256", "clearanceReceiptSHA256")
    if not all(isinstance(data.get(k), str) and sha.fullmatch(data[k]) for k in fields):
        raise ValueError("Malformed pinned build identity")
    checks = data["auditIPA"]
    if not isinstance(checks["size"], int) or not 1 <= checks["size"] <= 2_000_000_000 or not sha.fullmatch(checks["sha256"]):
        raise ValueError("Invalid local IPA byte proof")
    return {"source": source, "runtime": runtime, "arm64DeviceCompileAndLocalArchiveVerified": True,
            "originalIPAUnchanged": True, "physicalIPhoneVerified": False, "delivered": False,
            "localArchiveSHA256": checks["sha256"], "localArchiveBytes": checks["size"],
            "pythonNativeBinaries": 69, "pythonWheels": 3,
            **{k: data[k] for k in fields}}


if __name__ == "__main__":
    print(json.dumps(summary(json.loads(Path(sys.argv[1]).read_bytes()), sys.argv[2]), sort_keys=True))
