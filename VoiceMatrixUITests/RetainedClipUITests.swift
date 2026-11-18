import XCTest

@MainActor final class RetainedClipUITests:XCTestCase {
    private func scroll(_ app:XCUIApplication,up:Bool=true) {
        app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:up ? 0.72:0.28)).press(forDuration:0.01,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:up ? 0.28:0.72)))
    }
    private func reveal(_ target:XCUIElement,_ app:XCUIApplication,up:Bool=true) {
        for _ in 0..<12 {if target.exists && target.isHittable {return};scroll(app,up:up)}
        XCTAssertTrue(target.exists && target.isHittable)
    }
    private func open() -> XCUIApplication {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-tutorialSeen","YES"];app.launch()
        XCTAssertTrue(app.buttons["local-video-studio"].waitForExistence(timeout:30));app.buttons["local-video-studio"].tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout:10));return app
    }
    private func enter(_ field:XCUIElement,_ value:String,_ app:XCUIApplication) {
        reveal(field,app);field.tap()
        let old=field.value as? String ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+value)
        let exact=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",value),object:field)
        XCTAssertEqual(XCTWaiter.wait(for:[exact],timeout:10),.completed)
        app.buttons["local-video-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:10))
    }
    func testAValidRetainedIntervalPreparesWithoutStartingSeparation() {
        let app=open()
        let prepare=app.buttons["retained-clip-prepare"],consent=app.switches["retained-clip-authorization"]
        reveal(prepare,app);XCTAssertFalse(prepare.isEnabled);XCTAssertEqual(consent.value as? String,"0")
        let start=app.textFields["retained-clip-start"],seconds=app.textFields["retained-clip-seconds"]
        // Inputs are just above the preparation button; scroll back to the first.
        reveal(start,app,up:false);enter(start,"1",app);enter(seconds,"1",app)
        reveal(consent,app);consent.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(consent.value as? String,"1")
        reveal(seconds,app,up:false);enter(seconds,"11",app)
        reveal(prepare,app);XCTAssertEqual(consent.value as? String,"0")
        consent.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertEqual(consent.value as? String,"1");XCTAssertFalse(prepare.isEnabled)
        reveal(seconds,app,up:false);enter(seconds,"1.5",app)
        reveal(prepare,app);XCTAssertEqual(consent.value as? String,"0");XCTAssertFalse(prepare.isEnabled)
        consent.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
        XCTAssertTrue(prepare.isEnabled);prepare.tap()
        XCTAssertTrue(app.navigationBars["Separate vocals"].waitForExistence(timeout:30))
        // Exercise foreground recovery without starting inference. Acceptance may
        // already have finished, so this is not a deterministic interruption claim.
        XCUIDevice.shared.press(.home);app.activate()
        let status=app.staticTexts["separation-status"]
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label BEGINSWITH %@","Selected short clip ready."),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:30),.completed)
        XCTAssertEqual(app.buttons["separation-import"].label,"Retained clip 1.000–2.500 s")
        XCTAssertFalse(app.buttons["separation-cancel"].exists)
        // Source-only UI build intentionally has no models; never tap Separate.
        XCTAssertFalse(app.buttons["separation-run"].isEnabled)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Explicit retained interval prepared; no inference";shot.lifetime = .keepAlways;add(shot)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout:10))
        reveal(prepare,app);XCTAssertFalse(prepare.isEnabled);XCTAssertEqual(consent.value as? String,"0")
        app.terminate();app.launch();app.buttons["local-video-studio"].tap()
        reveal(prepare,app);XCTAssertFalse(prepare.isEnabled);XCTAssertEqual(consent.value as? String,"0")
        app.terminate()
    }
    func testBCorruptRetainedSourceIsRejectedWithoutPublishingClip() {
        let app=open()
        let corrupt=app.buttons["local-video-history-D6222222-2222-4222-8222-222222222222"]
        reveal(corrupt,app);corrupt.tap()
        let prepare=app.buttons["retained-clip-prepare"],consent=app.switches["retained-clip-authorization"]
        reveal(prepare,app,up:false);XCTAssertFalse(prepare.isEnabled)
        consent.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap();prepare.tap()
        let status=app.staticTexts["retained-clip-status"]
        let rejected=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label BEGINSWITH %@","Could not prepare this interval."),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[rejected],timeout:30),.completed)
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].exists)
        XCTAssertFalse(app.buttons["retained-clip-cancel"].exists)
        app.terminate()
    }
}
