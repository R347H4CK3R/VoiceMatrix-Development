"""Render only source files for an isolated, physical-iPhone test target."""
import hashlib
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
TEST = ROOT / "VoiceMatrixTests/StrictMatroskaF5Tests.swift"
PROJECT = ROOT / "project.yml"
APP = ROOT / "VoiceMatrix/App.swift"
APP_SHA256 = "a51e4485d53e12075dab7a4cf3a0e0e85f8a0d9544a165de7b4683a14f1a23ec"
TEST_SHA256 = "760fedc76c1fa50cb4954c66e574093c9e73934d3f06dcaba2699d7d4a0dfd8f"
PROJECT_SHA256 = "51dba50c828402ccc6a993f23810c5e83906cbebe7ac6868bf4099e46a390004"


def require_pin(source, digest):
    if hashlib.sha256(source.encode()).hexdigest() != digest:
        raise ValueError("Unreviewed input SHA-256; audit not rendered")


def replace_one(source, old, new):
    if source.count(old) != 1:
        raise ValueError("Pinned source anchor did not match exactly once")
    return source.replace(old, new, 1)


def render_runner(source):
    require_pin(source, TEST_SHA256)
    source = replace_one(source, "import XCTest\n@testable import VoiceMatrix\n", "")
    source = replace_one(source, "StrictMatroskaF5Tests: XCTestCase", "PhysicalAuditChecks")
    source = replace_one(source, "Bundle(for: Self.self)", "Bundle.main")
    wrappers = {"Equal": 40, "NotEqual": 3, "True": 4, "False": 5, "Nil": 2, "LessThanOrEqual": 2}
    for wrapper, expected in wrappers.items():
        source, n = re.subn(r"(?m)^(\s*)XCTAssert" + wrapper + r"\(", r"\1try audit" + wrapper + "(",
                            source)
        if n != expected:
            raise ValueError("Assertion count drift: " + wrapper)
    source = source.replace("XCTUnwrap(", "auditUnwrap(")
    if "XCT" in source:
        raise ValueError("Unconverted test parser token")
    return source


def render_project(source):
    require_pin(source, PROJECT_SHA256)
    source, found, _ = source.partition("\n  VoiceMatrixTests:\n")
    if not found:
        raise ValueError("Production target not found")
    source = replace_one(source, "name: VoiceMatrix\n", "name: VoiceMatrixPhysicalAudit\n")
    source = replace_one(source, "\n  VoiceMatrix:\n", "\n  VoiceMatrixPhysicalAudit:\n")
    source = replace_one(source, "      - Resources\n", """      - Resources
      - App.swift
      - LaptopSettings.json
    - probes/physical-audit/AuditApp.swift
    - .physical-audit-src/AuditChecks.swift
    - .physical-audit-src/ProductionViews.swift
    - path: .strict-f5-fixture/strict-f5-licensed.mp4
      buildPhase: resources
    - path: .strict-f5-fixture/strict-f5-fixture.json
      buildPhase: resources
    - path: tests/fixtures/DiagnosticVoices
      type: folder
      buildPhase: resources
""")
    source = replace_one(source, "PRODUCT_BUNDLE_IDENTIFIER: com.voicematrix.app",
                         "PRODUCT_BUNDLE_IDENTIFIER: com.voicematrix.physicalaudit")
    source = replace_one(source, "INFOPLIST_KEY_CFBundleDisplayName: VoiceMatrix", """
        INFOPLIST_KEY_CFBundleDisplayName: VoiceMatrix Audit
        SUPPORTED_PLATFORMS: iphoneos
        SUPPORTS_MACCATALYST: NO
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD: NO
        SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD: NO
        TARGETED_DEVICE_FAMILY: '1'
        """.strip())
    for unused in ("Phonon", "OpenVoice", "Separation"):
        source, n = re.subn(r"(?m)^    - path: VoiceMatrix/Resources/" + unused
                            + r"\n      type: folder\n(?:      optional: true\n)?      buildPhase: resources\n", "", source)
        if n != 1:
            raise ValueError("Unchanged entry for unused model not found")
    for selected in ("F5TTS", "Diarization", "ParakeetASR", "ParakeetNotices", "DiarizationNotices"):
        if selected == "DiarizationNotices":
            source = replace_one(source, "    - path: .physical-audit-assets/Diarization\n",
                 "    - path: .physical-audit-assets/DiarizationNotices\n      type: folder\n      buildPhase: resources\n"
                 "    - path: .physical-audit-assets/Diarization\n")
        else:
            source = replace_one(source, "    - path: VoiceMatrix/Resources/" + selected + "\n",
                                 "    - path: .physical-audit-assets/" + selected + "\n")
    # No shared entitlement or file sharing; generated project lives beside the original project.yml.
    return source + "\n"


def verify_runtime_checkout():
    paths = ["VoiceMatrix", "Vendors", "project.yml", "tools/python-runtime", "python-resolver",
             ":(exclude)Vendors/FluidAudio.inventory.json",
             ":(exclude)Vendors/FluidAudio/NOTICE-VoiceMatrix.txt"]
    source = "42da8f3ed18ca1c0f1462032db5dc05ce77362a1"
    checked = subprocess.run(["git", "diff", "--exit-code", source, "--", *paths],
                             cwd=ROOT, capture_output=True)
    untracked = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "--", *paths],
                               cwd=ROOT, capture_output=True)
    if checked.returncode or untracked.returncode or untracked.stdout:
        raise ValueError("Audit requires the exact reviewed production checkout")


def main(path):
    if path.exists():
        raise ValueError("Use a new output directory")
    verify_runtime_checkout()
    source = render_runner(TEST.read_text(encoding="utf-8"))
    project = render_project(PROJECT.read_text(encoding="utf-8"))
    views = APP.read_text(encoding="utf-8")
    require_pin(views, APP_SHA256)
    views = replace_one(views, "@main struct VoiceMatrixApp: App", "struct VoiceMatrixApp: App")
    path.mkdir(parents=False, exist_ok=False)
    (path / "AuditChecks.swift").write_text(source, encoding="utf-8")
    (path / "ProductionViews.swift").write_text(views, encoding="utf-8")
    (path / "project.yml").write_text(project, encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: prepare.py NEW_OUTPUT_DIRECTORY")
    try:
        main(Path(sys.argv[1]))
    except (OSError, ValueError) as error:
        sys.exit(str(error))
