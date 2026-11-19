import importlib.util
import json
from pathlib import Path
import unittest


def decide(payload):
    path = Path(__file__).resolve().parents[1] / "python-resolver/voicematrix_mkv_stage.py"
    spec = importlib.util.spec_from_file_location("vm_stage", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return json.loads(module.decide(payload))


class MKVStagePolicyTests(unittest.TestCase):
    job = "00000000-0000-4000-8000-000000000001"
    attempt = "00000000-0000-4000-8000-000000000002"
    a, m, d = "a" * 64, "b" * 64, "c" * 64
    reject = {"schemaVersion": 1, "action": "reject"}

    def request(self, stage):
        mkv = {"jobID": self.job, "attemptID": self.attempt,
               "acquisitionSHA256": self.a, "mkvSHA256": self.m}
        derived = {"jobID": self.job, "attemptID": self.attempt,
                   "mkvSHA256": self.m, "movSHA256": self.d}
        return {"schemaVersion": 1, "jobID": self.job, "attemptID": self.attempt,
                "stage": stage, "acquisitionSHA256": self.a,
                "mkv": mkv if stage != "acquisition" else None,
                "derived": derived if stage == "derivedVerified" else None}

    def test_exact_stage_decisions_and_deterministic_retry(self):
        for stage, action in (("acquisition", "prepare"), ("mkvVerified", "derive"),
                              ("derivedVerified", "complete")):
            payload = json.dumps(self.request(stage))
            expected = {"schemaVersion": 1, "jobID": self.job, "attemptID": self.attempt,
                        "stage": stage, "action": action}
            self.assertEqual(decide(payload), expected)
            self.assertEqual(decide(payload), expected)

    def test_rejects_wrong_parent_or_cross_attempt_receipts(self):
        for slot, key, value in (("mkv", "acquisitionSHA256", self.d),
                                 ("mkv", "attemptID", self.job),
                                 ("mkv", "jobID", self.attempt),
                                 ("derived", "mkvSHA256", self.a),
                                 ("derived", "attemptID", self.job),
                                 ("derived", "movSHA256", self.a),
                                 ("derived", "movSHA256", self.m)):
            request = self.request("derivedVerified")
            request[slot][key] = value
            self.assertEqual(decide(json.dumps(request)), self.reject)

    def test_rejects_unexpected_stage_or_schema_or_path(self):
        for change in ({"stage": "acquisition"}, {"stage": "mkvVerified"}, {"stage": "skip"},
                       {"schemaVersion": True}, {"schemaVersion": 1.0},
                       {"path": "/tmp/movie"}, {"jobID": self.job + "\n"},
                       {"acquisitionSHA256": "A" * 64}, {"derived": None}):
            self.assertEqual(decide(json.dumps({**self.request("derivedVerified"), **change})),
                             self.reject)
        request = self.request("mkvVerified")
        request["mkv"]["path"] = "/tmp/movie"
        self.assertEqual(decide(json.dumps(request)), self.reject)

    def test_rejects_duplicate_keys_unbounded_and_invalid_input(self):
        valid = json.dumps(self.request("acquisition"))
        for payload in (valid.replace('"mkv": null', '"mkv": null, "mkv": null'),
                        valid.replace('"mkv": null', '"mkv": NaN'),
                        " " * 4097, "[" * 2000 + "]" * 2000,
                        "\ud800", "[]", "null", b"{}", None):
            self.assertEqual(decide(payload), self.reject)
