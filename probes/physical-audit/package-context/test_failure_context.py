import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from failure_context import identify, observed_templates, LIMIT


class FailureContextTests(unittest.TestCase):
    def test_distinguishes_child_sandbox_application_from_file_error(self):
        result = identify("""Resolve Package Graph
xcodebuild: error: Could not resolve package dependencies:
  error: 'private-token': Invalid manifest (compiled with: ["/secret/path"])
  sandbox-exec: sandbox_apply: Operation not permitted""")
        self.assertEqual(result, ["manifest-invalid", "sandbox-apply-refused"])
        self.assertNotIn("secret", json.dumps(result))
        self.assertEqual(identify("sandbox-exec: /secret/path: Permission denied"), [])

    def test_distinguishes_build_plugin_and_container(self):
        self.assertEqual(identify("sandbox-exec: sandbox_apply_container: Operation not permitted\n"
                                  "error: compiler plugin not loaded: '/secret/path'; failed to initialize"),
                         ["sandbox-apply-container-refused", "compiler-plugin-not-loaded"])
        self.assertEqual(identify("unable to open output file '/private/file': 'Operation not permitted'"),
                         ["output-file-permission"])

    def test_no_partial_or_unknown_message_disclosure(self):
        self.assertEqual(identify("some command contains sandbox-exec: sandbox_apply: Operation not permitted\n"
                                  "sandbox-exec: sandbox_apply: Operation not permitted token"), [])
        self.assertEqual(identify(None), [])

    def test_truncation_never_treats_a_partial_line_as_a_template(self):
        marker = b"sandbox-exec: sandbox_apply: Operation not permitted"
        with TemporaryDirectory() as scratch:
            log = Path(scratch) / "log"
            half = LIMIT // 2
            # Apparent complete template at either truncated edge is actually embedded.
            log.write_bytes(b"x" * (half - len(marker) - 1) + b"\n" + marker
                            + b"x" * 300 + marker + b"\n"
                            + b"x" * (half - len(marker) - 1))
            self.assertEqual(observed_templates(log), [])
            log.write_bytes(b"x" * LIMIT + b"\n" + marker + b"\n")
            self.assertEqual(observed_templates(log), ["sandbox-apply-refused"])
