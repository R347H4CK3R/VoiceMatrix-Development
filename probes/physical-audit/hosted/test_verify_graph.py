import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parent


def load(name):
    s = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(s)
    s.loader.exec_module(module)
    return module


class HostedAuditGraphDesign(unittest.TestCase):
    def test_current_canonical_graph_has_only_vendor_migration(self):
        module = load("verify_graph")
        raw = module.HISTORICAL.read_bytes()
        current = module.current_graph(raw)
        self.assertEqual(hashlib.sha256(current).hexdigest(), module.CANONICAL_SHA)
        self.assertEqual(module.summary(current, current)["reason"], "canonical-exact")
        self.assertEqual(module.summary(current, raw)["reason"], "pin-mismatch")
        self.assertEqual(module.summary(current, current + b" ")["reason"], "semantic-match-byte-drift")

    def test_dependency_only_project_has_same_package_declarations_and_no_models(self):
        module = load("verify_graph")
        local = ROOT.parent / "prepare.py"
        spec = importlib.util.spec_from_file_location("source_prepare", local)
        prep = importlib.util.module_from_spec(spec); spec.loader.exec_module(prep)
        project = prep.render_project(prep.PROJECT.read_text())
        probe = module.graph_projection(project)
        self.assertEqual(module.dependencies(probe), module.dependencies(project))
        self.assertNotIn("preGenCommand", probe)
        self.assertNotIn("strict-f5-licensed.mp4", probe)
        self.assertNotIn("Python.xcframework", probe)
        self.assertIn("Vendors/ONNXRuntime", probe)
        self.assertIn("Vendors/FluidAudio", probe)

if __name__ == "__main__":
    unittest.main()
