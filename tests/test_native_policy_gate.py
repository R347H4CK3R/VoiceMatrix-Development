import io
import pathlib
import unittest
from tools import native_policy_gate as gate

class NativePolicyGateTests(unittest.TestCase):
    def run_case(self, method):
        case = type('Case', (unittest.TestCase,), {'test_case': method})
        return gate.run(unittest.defaultTestLoader.loadTestsFromTestCase(case), stream=io.StringIO())

    def test_success_requires_execution(self):
        self.assertEqual(self.run_case(lambda self: self.assertTrue(True)), 0)

    def test_skipped_native_check_is_not_success(self):
        self.assertNotEqual(self.run_case(lambda self: self.skipTest('no Swift')), 0)

    def test_failure_is_not_success(self):
        self.assertNotEqual(self.run_case(lambda self: self.fail('bad policy')), 0)

    def test_empty_suite_is_not_success(self):
        self.assertNotEqual(gate.run(unittest.TestSuite(), stream=io.StringIO()), 0)

    def test_circleci_runs_gate_before_models(self):
        text=(pathlib.Path(__file__).resolve().parents[1]/'.circleci/config.yml').read_text()
        self.assertLess(text.index('python3 tools/native_policy_gate.py'), text.index('python3 tools/bundle_diarization.py'))
