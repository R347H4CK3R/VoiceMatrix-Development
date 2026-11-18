import XCTest

@MainActor final class VocalSeparationUITests:XCTestCase {
    func testSeparationRequiresExplicitInputAndKeepsExistingRoutes() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-tutorialSeen","YES"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:30))
        let route=app.buttons["vocal-separation"]
        for _ in 0..<8 {if route.isHittable {break};app.swipeUp()}
        XCTAssertTrue(route.isHittable);route.tap()
        XCTAssertTrue(app.buttons["separation-import"].waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["separation-run"].isEnabled)
        XCTAssertTrue(app.buttons["separation-cancel"].waitForNonExistence(timeout:10))
        XCTAssertTrue(app.staticTexts["separation-status"].label.contains("Nothing is uploaded"))
        app.terminate();app.launch();app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.buttons["local-video-studio"].waitForExistence(timeout:10))
    }
}
