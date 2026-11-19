"""Inspect an owner-signed audit app locally; no signing, installation, upload or account access."""
import argparse
from pathlib import Path
import plistlib
import re
import subprocess

AUDIT_ID = "com.voicematrix.physicalaudit"
GROUPS = "com.apple.security.application-groups"
ICLOUD = "com.apple.developer.icloud-container-identifiers"
KEYCHAIN = "keychain-access-groups"


def isolated(info, entitlements):
    tag = entitlements.get("application-identifier")
    if not isinstance(tag, str) or not re.fullmatch(r"[A-Z0-9]{10}\." + re.escape(AUDIT_ID), tag):
        return False
    team = tag.split(".")[0]
    if info.get("CFBundleIdentifier") != AUDIT_ID or info.get("UIFileSharingEnabled", False):
        return False
    if entitlements.get("com.apple.developer.team-identifier") != team:
        return False
    if any(value for key, value in entitlements.items()
           if key in (GROUPS, ICLOUD) or "icloud" in key or "ubiquity" in key):
        return False
    return entitlements.get(KEYCHAIN, []) in ([], [tag])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app", type=Path, help="A local, extracted, independently owner-signed audit .app")
    args = parser.parse_args()
    path = args.app
    if not path.is_dir() or path.is_symlink():
        parser.error("Expected a local regular .app directory")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(path)],
                   check=True, timeout=60, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    raw = subprocess.check_output(["/usr/bin/codesign", "-d", "--entitlements", ":-", str(path)],
                                  stderr=subprocess.PIPE, timeout=15)
    if not isolated(plistlib.loads((path / "Info.plist").read_bytes()), plistlib.loads(raw)):
        parser.error("Effective audit bundle identity or sandbox entitlements differ. Do not install.")
    print("Signed audit identity isolated; physical iPhone execution has not been tested.")


if __name__ == "__main__":
    main()
