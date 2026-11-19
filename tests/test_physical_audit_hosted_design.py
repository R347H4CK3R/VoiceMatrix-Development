import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1] / "probes/physical-audit/hosted"


def load(name):
    s = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(s)
    s.loader.exec_module(module)
    return module


class HostedAuditDesign(unittest.TestCase):
    def test_donor_extracts_only_individually_verified_f5_and_diarization(self):
        module = load("derive_baseline_models")
        sample = {"size": 1, "sha256": hashlib.sha256(b"a").hexdigest()}
        locks = {k: {"payload": sample} for k in ("F5TTS", "Diarization")}
        data = io.BytesIO()
        with zipfile.ZipFile(data, "w") as z:
            for path in ("F5TTS/payload", "Diarization/payload", "ParakeetASR/old", "LaptopSettings.json"):
                z.writestr("Payload/VoiceMatrix.app/" + path, b"a")
        with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(data) as z:
            root = Path(tmp)
            module.extract_pins(z, module.members(z), root / "good", locks)
            self.assertEqual({p.relative_to(root / "good").as_posix() for p in (root / "good").rglob("*") if p.is_file()},
                             {"F5TTS/payload", "Diarization/payload"})
            locks["F5TTS"]["payload"] = {**sample, "sha256": "b" * 64}
            with self.assertRaises(ValueError):
                module.extract_pins(z, module.members(z), root / "bad", locks)

    def test_metadata_ignores_private_fields_and_cannot_claim_delivery(self):
        module = load("report_metadata")
        values = {"auditSourceRevision": "a"*40, "exactRuntime": "42da8f3ed18ca1c0f1462032db5dc05ce77362a1",
                  "auditBundleID": "com.voicematrix.physicalaudit", "baselinePreserved": True, "published": False, "physicalIPhoneVerified": False,
                  "signedBundleIsolationVerified": False, "python": {"native": 69, "wheels": 3},
                  "graphSHA256": "b"*64, "xcodegenSHA256": "c"*64, "clearanceReceiptSHA256": "d"*64,
                  "auditIPA": {"sha256": "e"*64, "size": 20000}, "private": "ignored", "localPath": "ignored"}
        row = module.summary(values, "a"*40)
        self.assertFalse(row["delivered"])
        self.assertNotIn("private", row)
        with self.assertRaises(ValueError):
            module.summary({**values, "physicalIPhoneVerified": True}, "a"*40)
        with self.assertRaises(ValueError):
            module.summary({**values, "exactRuntime": "not-an-allowed-log-value"}, "a"*40)
