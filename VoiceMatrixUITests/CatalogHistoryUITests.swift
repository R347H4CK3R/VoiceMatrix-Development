import XCTest
import CoreGraphics

/// Uses real app storage/UI with an explicitly unverified synthetic history fixture.
/// Does not test synthesis, ASR, third-party delivery or physical-device playback.
@MainActor final class CatalogHistoryUITests: XCTestCase {
    func testHistoryPlaybackSaveShareRestartAndConfirmedDelete() {
        executionTimeAllowance=240;continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-tutorialSeen","YES","-ui-test-import"];app.launch()
        func openHistory() {
            XCTAssertTrue(app.tabBars.buttons["Voices"].waitForExistence(timeout:30));app.tabBars.buttons["Voices"].tap()
            let history=app.buttons["Retained speech history"]
            reveal(history,in:app);history.tap()
            let request=app.staticTexts["Synthetic retained speech UI fixture"]
            reveal(request,in:app);XCTAssertTrue(request.exists)
            XCTAssertFalse(app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","Last word-checked result")).firstMatch.exists)
        }
        openHistory()
        let listen=app.buttons.matching(identifier:"Listen / Replay").element(boundBy:0);reveal(listen,in:app);listen.tap()
        let stop=app.buttons["Stop"];XCTAssertTrue(stop.waitForExistence(timeout:10));stop.tap()
        XCTAssertTrue(stop.waitForNonExistence(timeout:10))
        let saves=app.buttons.matching(identifier:"save-recording");XCTAssertEqual(saves.count,2)
        let save=saves.element(boundBy:0);reveal(save,in:app);save.tap()
        expectation(for:NSPredicate(format:"enabled == false"),evaluatedWith:save);waitForExpectations(timeout:10)
        XCTAssertEqual(save.label,"Saved")
        let secondSave=saves.element(boundBy:1);reveal(secondSave,in:app);XCTAssertTrue(secondSave.isEnabled,"Other attempt with same basename must remain independently saveable");secondSave.tap()
        expectation(for:NSPredicate(format:"enabled == false"),evaluatedWith:secondSave);waitForExpectations(timeout:10);XCTAssertEqual(secondSave.label,"Saved")
        let share=app.buttons.matching(identifier:"Share Audio").element(boundBy:0);reveal(share,in:app);share.tap()
        let saveFiles=app.buttons["Save to Files"],copy=app.buttons["Copy"]
        XCTAssertTrue(saveFiles.waitForExistence(timeout:10) || copy.waitForExistence(timeout:5),"System share sheet must expose a real export action; no external destination selected")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Retained unverified audio system sharing";shot.lifetime = .keepAlways;add(shot)
        let close=app.buttons["Close"]
        if close.exists && close.isHittable { close.tap() } else { app.swipeDown() }
        app.terminate();app.launchArguments=["-tutorialSeen","YES"];app.launch();openHistory()
        let remove=app.buttons.matching(identifier:"Delete this retained result").element(boundBy:0);reveal(remove,in:app);remove.tap()
        let confirm=app.buttons["Delete retained result"];XCTAssertTrue(confirm.waitForExistence(timeout:10))
        app.buttons["Cancel"].tap();XCTAssertTrue(remove.exists,"Cancel must retain the history item")
        reveal(remove,in:app);remove.tap();XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap()
        XCTAssertTrue(app.staticTexts["Synthetic retained speech UI fixture"].waitForNonExistence(timeout:10))
        app.terminate();app.launch();XCTAssertTrue(app.tabBars.buttons["Voices"].waitForExistence(timeout:30));app.tabBars.buttons["Voices"].tap()
        let history=app.buttons["Retained speech history"];reveal(history,in:app);history.tap()
        XCTAssertFalse(app.staticTexts["Synthetic retained speech UI fixture"].exists)
        let remaining=app.staticTexts["Second retained speech UI fixture"];reveal(remaining,in:app);XCTAssertTrue(remaining.exists)
        let secondDelete=app.buttons["Delete this retained result"];reveal(secondDelete,in:app);secondDelete.tap();XCTAssertTrue(confirm.waitForExistence(timeout:10));confirm.tap();XCTAssertTrue(remaining.waitForNonExistence(timeout:10))
        let choose=app.buttons["choose-character"];reveal(choose,in:app);choose.tap()
        XCTAssertTrue(app.buttons["select-character-diagnostic-neutral"].waitForExistence(timeout:15),"Deleting output must retain imported voice")
    }
    private func reveal(_ item:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<12 {
            let top=app.navigationBars.firstMatch.frame.maxY+16,bottom=app.tabBars.firstMatch.frame.minY-40
            if item.exists && item.isHittable && item.frame.minY>top && item.frame.maxY<bottom { return }
            let dy:CGFloat = item.exists && item.frame.minY<=top ? 120 : -120
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.55))
            start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:0,dy:dy)))
        }
        XCTAssertTrue(item.exists && item.isHittable,"History control must be reachable")
    }
}
