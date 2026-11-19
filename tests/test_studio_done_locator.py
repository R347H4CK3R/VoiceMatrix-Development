import unittest
from pathlib import Path

class StudioDoneLocatorTests(unittest.TestCase):
    def test_accessory_done_is_unique_and_dismisses_keyboard(self):
        source = (Path(__file__).resolve().parents[1] / "VoiceMatrixUITests/LocalVideoStudioUITests.swift").read_text()
        self.assertIn('app.toolbars.buttons.matching(identifier: "Done")', source)
        self.assertIn('XCTAssertEqual(done.count, 1', source)
        self.assertIn('XCTAssertTrue(done.element.isHittable)', source)
        self.assertIn('done.element.tap()', source)
        self.assertIn('NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch', source)
        self.assertIn('XCTWaiter.wait(for: [dismissed], timeout: 10)', source)
        self.assertNotIn('app.buttons["Done"].tap()', source)
