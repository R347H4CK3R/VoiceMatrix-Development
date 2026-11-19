import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("materialization", HERE / "materialization.py")
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class MaterializationTests(unittest.TestCase):
    @staticmethod
    def binary(platform=2, payload=b""):
        return (struct.pack("<8I", 0xFEEDFACF, 0x100000C, 0, 6, 1, 24, 0, 0)
                + struct.pack("<6I", 0x32, 24, platform, 26 << 16, 26 << 16, 0) + payload)

    def fixture(self, root):
        rows = []
        for target, pin in gate.PINS.items():
            if not pin["required"]:
                continue
            xc = root / "artifacts" / pin["identity"] / (target + ".xcframework")
            lib = xc / "ios-arm64"
            lib.mkdir(parents=True)
            (lib / "lib.a").write_bytes(self.binary())
            (xc / "Info.plist").write_bytes(plistlib.dumps({"AvailableLibraries": [{
                "LibraryIdentifier": "ios-arm64", "LibraryPath": "lib.a",
                "SupportedPlatform": "ios", "SupportedArchitectures": ["arm64"]
            }]}))
            rows.append({"targetName": target, "packageRef": {"identity": pin["identity"]},
                         "path": str(xc), "source": {"type": "remote", "url": pin["url"], "checksum": pin["sha"]}})
        return rows

    def save(self, root, rows):
        (root / "workspace-state.json").write_text(json.dumps({"version": 6, "object": {"artifacts": rows}}))

    def test_checks_known_pins_and_device_slices_without_reporting_routes(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td); rows = self.fixture(p); self.save(p, rows)
            result = gate.inspect(p)
            self.assertTrue(result["requiredValidated"])
            self.assertIn("not-selected", {v["status"] for v in result["binaries"].values()})
            self.assertNotIn(td, repr(result))
            self.assertNotIn("https://", repr(result))

    def test_missing_or_wrong_state_pin_and_real_slice_fail(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td); rows = self.fixture(p); self.save(p, rows[:1])
            self.assertFalse(gate.inspect(p)["requiredValidated"])
            rows[0]["source"]["checksum"] = "a" * 64
            self.save(p, rows)
            result = gate.inspect(p)
            self.assertIn("state-pin-mismatch", {v["status"] for v in result["binaries"].values()})
            rows[0]["source"]["checksum"] = gate.PINS[rows[0]["targetName"]]["sha"]
            (Path(rows[0]["path"]) / "ios-arm64" / "lib.a").unlink()
            self.save(p, rows)
            self.assertIn("missing-ios-device-slice", {v["status"] for v in gate.inspect(p)["binaries"].values()})

    def test_owned_artifacts_root_and_device_architecture_are_proven(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td); rows = self.fixture(p); self.save(p, rows)
            binary = Path(rows[0]["path"]) / "ios-arm64" / "lib.a"
            binary.write_bytes(self.binary(platform=7))
            self.assertIn("invalid-ios-device-binary", {v["status"] for v in gate.inspect(p)["binaries"].values()})
            (p / "artifacts").rename(p / "otherwise-present")
            (p / "artifacts").symlink_to(p / "otherwise-present", target_is_directory=True)
            result = gate.inspect(p)
            self.assertFalse(result["requiredValidated"])
            self.assertEqual(result["status"], "unowned-artifact-store")

    def test_symlink_alias_inside_own_artifacts_cannot_pass(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td); rows = self.fixture(p)
            own = p / "artifacts"; alias = own / "alias-to-root"
            alias.symlink_to(own, target_is_directory=True)
            rows[0]["path"] = str(alias / Path(rows[0]["path"]).relative_to(own))
            self.save(p, rows)
            self.assertIn("outside-owned-artifacts", {v["status"] for v in gate.inspect(p)["binaries"].values()})

    def test_ios_static_archive_member_is_checked(self):
        with tempfile.TemporaryDirectory() as td:
            p=Path(td)/"lib.a"
            b=self.binary()
            head = b"member.o/".ljust(16)+b"0".ljust(12)+b"0".ljust(6)+b"0".ljust(6)+b"644".ljust(8)+str(len(b)).encode().ljust(10)+b"`\n"
            p.write_bytes(b"!<arch>\n"+head+b)
            self.assertTrue(gate.ios_device_binary(p))
            p.write_bytes(b"!<arch>\n"+head+self.binary(platform=7))
            self.assertFalse(gate.ios_device_binary(p))

    def test_escape_and_content_change_are_not_hidden(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td); rows = self.fixture(p); self.save(p, rows)
            one = gate.inspect(p)
            (Path(rows[0]["path"]) / "ios-arm64" / "lib.a").write_bytes(self.binary(payload=b"changed byte"))
            two = gate.inspect(p)
            self.assertNotEqual(one["binaries"], two["binaries"])
            rows[0]["path"] = "/outside/private/root"
            self.save(p, rows)
            self.assertIn("outside-owned-artifacts", {v["status"] for v in gate.inspect(p)["binaries"].values()})


if __name__ == "__main__":
    unittest.main()
