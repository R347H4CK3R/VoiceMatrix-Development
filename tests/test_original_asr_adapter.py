"""Portable structural contract; native compilation and recognition are separate."""
import hashlib
import subprocess
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
BASE = "4ed344a8bb859e841c35041f3f07b9510a930492"
TDT = Path("Vendors/FluidAudio/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT")
PIPE = TDT / "AsrManager+Pipeline.swift"
APP = Path("VoiceMatrix/OnDeviceTranscription.swift")

def current(path):
    return (ROOT / path).read_text()

def base(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT, text=True)

class AdapterContracts(unittest.TestCase):
    def test_app_only_changes_local_frontend_selection(self):
        self.assertIn("localFrontend: .originalNemo231", current(APP))
        self.assertEqual(current(APP).replace(",\n                                    localFrontend: .originalNemo231", ""), base(APP))

    def test_only_local_exact_version_opt_in(self):
        source = current(TDT / "AsrModels.swift")
        local = source.split("public static func loadLocal(", 1)[1].split("public static func load(", 1)[0]
        self.assertIn("localFrontend: AsrLocalFrontend = .coreML", local)
        self.assertIn("version == .v3, encoderPrecision == .int8V2", local)
        self.assertNotIn("ModelHub", local)
        self.assertIn("verifyOriginalNemo231Encoder", local)
        self.assertIn("Frontend/window.f32le", local)
        self.assertIn("Frontend/filterbank.f32le", local)

    def test_typed_frontend_state_reaches_cleanup(self):
        source = current(TDT / "AsrManager.swift")
        self.assertEqual(source.count("self.frontend = models.frontend"), 2)
        self.assertIn("frontend = nil", source)
        self.assertIn("frontend != nil && encoderModel != nil", source)

    def test_switch_preserves_retry_and_decoder_blocks(self):
        source = current(PIPE)
        self.assertIn("case .originalNemo231(let native):", source)
        self.assertIn("validSamples: declaredLength ?? inputAudio.count", source)
        before = base(PIPE)
        self.assertEqual(source.split("        let preprocessorInput: MLFeatureProvider?", 1)[0],
                         before.split("        let preprocessorInput = try await", 1)[0])
        anchor = "            let encoderOutputProvider: MLFeatureProvider"
        terminal = "    /// The encoder input with"
        self.assertEqual(source.split(anchor, 1)[1].split("    /// Adapt only the original frontend", 1)[0],
                         before.split(anchor, 1)[1].split(terminal, 1)[0])

    def test_native_encoder_input_is_precise_and_fail_closed(self):
        source = current(PIPE)
        self.assertIn("shape: [1, 128, 1501], dataType: .float32", source)
        self.assertIn("shape: [1], dataType: .int32", source)
        self.assertIn("let fallback = originalInput?.featureValue", source)
        self.assertIn("guard audio.count == ASRConstants.maxModelSamples", source)
        frontend = current(TDT / "Parakeet231Frontend.swift")
        self.assertIn("Parakeet231Frontend: Sendable", frontend)
        self.assertEqual(
            hashlib.sha256(frontend.replace("Parakeet231Frontend: Sendable", "Parakeet231Frontend").encode()).hexdigest(),
            "0204480006dab281f09e2c7d45c8d98c3114efac464b48beab1c478afd71ff07",
        )

if __name__ == "__main__":
    unittest.main()
