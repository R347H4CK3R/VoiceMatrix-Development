import importlib.util
import io
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def load_gate():
    spec = importlib.util.spec_from_file_location("physical_gate", ROOT / "probes/physical-audit/packaging_gate.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AuditPackagingTests(unittest.TestCase):
    def test_exact_replacement_model_locks(self):
        gate = load_gate()
        sizes = {name: (len(lock), sum(row["size"] for row in lock.values()))
                 for name, lock in gate.models(ROOT).items()}
        self.assertEqual(sizes, {"ParakeetASR": (19, 631788023), "Diarization": (26, 21639362),
                                 "F5TTS": (7, 702250584)})

    def test_approval_cannot_authorize_public_or_commercial_distribution(self):
        gate = load_gate()
        receipt = {**gate.required_receipt(), "approvedBy": "Independent review",
                   "approvalDateUTC": "2026-11-19", "graphSHA256": gate.GRAPH_SHA,
                   "xcodegenSHA256": "b" * 64, "xcodeVersion": "Xcode 26.6",
                   "iphoneOSSDK": "26.5"}
        gate.require_receipt(receipt)
        self.assertFalse(gate.required_receipt().get("approvedBy"))
        with self.assertRaises(ValueError):
            gate.require_receipt({**receipt, "approvalDateUTC": "no-date"})
        for wrong in ("commercial", "public", "unknown"):
            with self.assertRaises(ValueError):
                gate.require_receipt({**receipt, "scope": wrong})

    def test_archive_path_tampering_and_unlisted_models_rejected(self):
        gate = load_gate()
        with tempfile.TemporaryDirectory() as root:
            buf = io.BytesIO()
            with zipfile.ZipFile(buf, "w") as z:
                z.writestr("Payload/VoiceMatrixPhysicalAudit.app/../other", b"fixture")
            with zipfile.ZipFile(io.BytesIO(buf.getvalue())) as z:
                with self.assertRaises(ValueError):
                    gate.archive_files(z)
            target = Path(root)
            (target / "file").write_bytes(b"test")
            with self.assertRaises(ValueError):
                gate.exact_tree(target, {})

    def test_arm64_simulator_binary_cannot_masquerade_as_device(self):
        gate = load_gate()
        header = struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 2, 1, 24, 0, 0)
        def example(platform):
            return io.BytesIO(header + struct.pack("<6I", 0x32, 24, platform, 26 << 16, 26 << 16, 0))
        gate.verify_device_binary(example(2))
        with self.assertRaises(ValueError):
            gate.verify_device_binary(example(7))

    def test_python_stage_creates_fresh_sdk_directory(self):
        gate = load_gate()
        with tempfile.TemporaryDirectory() as work:
            root = Path(work) / "source"; root.mkdir()
            sdk = Path(work) / "previously-reviewed-cache"; sdk.mkdir()
            (root / "Vendors").mkdir()
            (sdk / gate.SDK).write_bytes(b"test SDK")
            wheels = sdk / "wheels"; wheels.mkdir()
            for i in range(3):
                (wheels / f"wheel-{i}.whl").write_bytes(bytes([i]))
            requirements = root / "tools/python-runtime/requirements-ios-resolver.txt"
            requirements.parent.mkdir(parents=True)
            requirements.write_text("\n".join("--hash=sha256:" + gate.digest(p) for p in wheels.iterdir()))
            with patch.object(gate, "SDK_SHA", gate.digest(sdk / gate.SDK)):
                gate.stage_python(root, sdk)
            self.assertEqual((root / "Vendors/Python" / gate.SDK).read_bytes(), b"test SDK")
            self.assertEqual(len(list((root / ".python-runtime/wheels").iterdir())), 3)

    def test_signed_audit_rejects_another_app_or_shared_group(self):
        signed_path = ROOT / "probes/physical-audit/verify_signed_identity.py"
        spec = importlib.util.spec_from_file_location("signed_audit", signed_path)
        signed = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(signed)
        tag = "ABC01DE234." + signed.AUDIT_ID
        metadata = {"CFBundleIdentifier": signed.AUDIT_ID, "UIFileSharingEnabled": False}
        entitlements = {"application-identifier": tag, "com.apple.developer.team-identifier": "ABC01DE234",
                        "keychain-access-groups": [tag]}
        self.assertTrue(signed.isolated(metadata, entitlements))
        self.assertFalse(signed.isolated({**metadata, "CFBundleIdentifier": "com.voicematrix.app"}, entitlements))
        self.assertFalse(signed.isolated(metadata, {**entitlements, signed.GROUPS: ["group.shared"]}))
        self.assertFalse(signed.isolated(metadata, {**entitlements, signed.KEYCHAIN: ["ABC01DE234.com.voicematrix.app"]}))

    def test_source_plan_defaults_to_non_dispatch_and_immutable_baseline(self):
        gate = load_gate()
        self.assertEqual(gate.BASELINE["size"], 1330407101)
        runner = (ROOT / "probes/physical-audit/build_native.sh").read_text()
        self.assertNotIn("bundle_asr.py", runner)
        self.assertIn("sandbox-exec", runner)
        self.assertIn("CODE_SIGNING_ALLOWED=NO", runner)
        self.assertNotIn("gh release", runner)
        self.assertNotIn("curl ", runner)
        self.assertNotIn("git push", runner)
