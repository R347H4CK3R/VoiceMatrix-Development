import json
from pathlib import Path
import tempfile
import unittest
from tools.seed_rvc_history_ui import FILE, fixture, seed, check

class FixtureTests(unittest.TestCase):
    def test_seed_is_exclusive_canonical_and_check_requires_copy(self):
        with tempfile.TemporaryDirectory() as td:
            root=Path(td);seed(root)
            data,receipt=fixture()
            self.assertEqual(data[:4],b'RIFF')
            self.assertEqual(len(data),receipt['bytes'])
            with self.assertRaises(FileExistsError):seed(root)
            with self.assertRaises(AssertionError):check(root)
            copied=root/'Library/Caches/RVCPreview/rvc-action-test'/FILE
            copied.parent.mkdir(parents=True);copied.write_bytes(data)
            check(root)
            copied.write_bytes(b'corrupt')
            with self.assertRaises(AssertionError):check(root)
