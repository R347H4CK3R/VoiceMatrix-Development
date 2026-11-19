from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "VoiceMatrix"


class StrictMKVRouteTests(unittest.TestCase):
    def test_strict_acquisition_is_opt_in_and_persists_original_before_deriving(self):
        acquisition = (ROOT / "LocalMediaAcquisition.swift").read_text()
        studio = (ROOT / "LocalVideoStudio.swift").read_text()
        self.assertIn("prepareMatroska: Bool = true", acquisition)
        self.assertEqual(acquisition.count("if prepareMatroska { try await retainMatroska"), 2)
        self.assertLess(studio.index('try update("Original retained"'), studio.index("LocalMatroskaWorkflow.run("))
        self.assertIn("prepareMatroska: false", studio)
        self.assertIn("strict.original == nil", studio)

    def test_strict_derived_source_and_read_only_export_are_distinct(self):
        studio = (ROOT / "LocalVideoStudio.swift").read_text()
        self.assertIn("current?.sourceFile = output.derived.file", studio)
        self.assertIn("current?.sourceSHA256 = output.derived.sha256", studio)
        self.assertIn("job.validStrictMatroska", studio)
        self.assertIn("LocalMatroskaWorkflow.validatePublished(jobDirectory: directory", studio)
        self.assertIn("strictForNewLink: current?.strictMatroska != nil", studio)

    def test_published_consumers_require_complete_bound_journal(self):
        studio = (ROOT / "LocalVideoStudio.swift").read_text()
        workflow = (ROOT / "LocalMatroskaWorkflow.swift").read_text()
        self.assertEqual(studio.count("LocalMatroskaWorkflow.validatePublished("), 4)
        section = workflow.split("static func validatePublished(", 1)[1].split("static func availableCapacity", 1)[0]
        for required in ("journal.complete", "journal.attemptID == attemptID", "validateJournalKeys",
                         "LocalMediaAcquisition.verify", "load() == snapshot"):
            self.assertIn(required, section)
        for illegal in ("admit(", "remux(", "derive(", ".write("):
            self.assertNotIn(illegal, section)
