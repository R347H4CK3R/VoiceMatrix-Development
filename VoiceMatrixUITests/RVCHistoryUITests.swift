import XCTest

/// Synthetic storage/UI recovery only; not inference or audio-quality proof.
@MainActor final class RVCHistoryUITests:XCTestCase {
    private func openHistory(_ app:XCUIApplication) {
            XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:30))
            let optional=app.buttons["Optional laptop tools"]
            for _ in 0..<8 {if optional.isHittable {break};app.swipeUp()}
            if !app.buttons["laptop-rvc"].exists {optional.tap()}
            let laptop=app.buttons["laptop-rvc"]
            for _ in 0..<8 {if laptop.isHittable {break};app.swipeUp()}
            XCTAssertTrue(laptop.isHittable);laptop.tap()
            XCTAssertTrue(app.navigationBars["Laptop RVC"].waitForExistence(timeout:15))
            let route=app.buttons["rvc-local-diagnostic"]
            for _ in 0..<8 {if route.isHittable {break};app.swipeUp()}
            XCTAssertTrue(route.isHittable);route.tap()
            XCTAssertTrue(app.navigationBars["On-device RVC"].waitForExistence(timeout:15))
    }
    func testSeededHistorySelectsVerifiedCopyAcrossRelaunch() {
        let app=XCUIApplication()
        app.launchArguments=["-tutorialSeen","YES"]
        for _ in 0..<2 {
            app.launch();openHistory(app)
            let saved=app.buttons["rvc-history-9479750A-0204-4C84-AB2A-F193D8E826A1"]
            for _ in 0..<12 {if saved.isHittable {break};app.swipeUp()}
            XCTAssertTrue(saved.waitForExistence(timeout:10))
            XCTAssertTrue(saved.isEnabled);saved.tap()
            let status=app.staticTexts["rvc-preview-status"]
            let ready=NSPredicate(format:"label == %@","Saved diagnostic audio verified. Ready to listen or share.")
            expectation(for:ready,evaluatedWith:status)
            waitForExpectations(timeout:30)
            let label=app.staticTexts["Diagnostic preview of UI synthetic history fixture.wav"]
            for _ in 0..<8 {if label.isHittable {break};app.swipeUp()}
            XCTAssertTrue(label.exists)
            let listen=app.buttons["Listen / Replay"]
            for _ in 0..<4 {if listen.isHittable {break};app.swipeUp()}
            XCTAssertTrue(listen.exists);XCTAssertTrue(listen.isEnabled)
            XCTAssertTrue(app.buttons["save-recording"].exists)
            XCTAssertTrue(app.buttons["Share Audio"].exists)
            // Do not send/share or claim inference quality; verify actions are ready.
            app.terminate()
        }
    }
    func testHistoryRemainsReachableWithoutInstalledModelsAcrossRelaunch() {
        let app=XCUIApplication()
        app.launchArguments=["-tutorialSeen","YES"]
        for _ in 0..<2 {
            app.launch()
            openHistory(app)
            let notice=app.staticTexts["rvc-history-notice"]
            for _ in 0..<12 {if notice.isHittable {break};app.swipeUp()}
            XCTAssertTrue(notice.waitForExistence(timeout:10))
            XCTAssertFalse(notice.label.isEmpty)
            XCTAssertTrue(app.staticTexts["rvc-history-empty"].exists)
            app.terminate()
        }
    }
}
