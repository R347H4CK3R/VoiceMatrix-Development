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
    func testSeededVocalsHandoffRequiresFreshAuthorizationAcrossNavigation() {
        continueAfterFailure=false
        let app=XCUIApplication();app.launchArguments=["-tutorialSeen","YES"];app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:30))
        let route=app.buttons["vocal-separation"]
        for _ in 0..<8 {if route.exists && route.isHittable {break};app.swipeUp()}
        route.tap()
        let handoff=app.buttons["separation-reference-B2E33332-AE5E-423F-9B44-555555555551"]
        let corrupt=app.buttons["separation-reference-B2E33332-AE5E-423F-9B44-555555555552"]
        func reveal(_ target:XCUIElement) {
            for _ in 0..<10 {
                if target.exists && target.isHittable {return}
                app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.72)).press(forDuration:0.01,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.28)))
            }
            XCTAssertTrue(target.exists && target.isHittable)
        }
        for _ in 0..<2 {
            reveal(handoff)
            XCTAssertFalse(corrupt.exists)
            XCTAssertTrue(handoff.isEnabled);handoff.tap()
            let selected=app.staticTexts["local-video-separated-source"]
            XCTAssertTrue(selected.waitForExistence(timeout:15))
            XCTAssertTrue(selected.label.contains("Separated vocals selected"))
            XCTAssertTrue(app.staticTexts["Local media selected"].exists)
            let url=app.textFields["local-video-url"]
            // An empty text field may expose its placeholder as its accessibility value.
            let urlValue=url.value as? String ?? ""
            XCTAssertTrue(urlValue.isEmpty || urlValue=="YouTube or supported HTTPS media URL")
            let consent=app.switches["local-video-authorization"]
            reveal(consent)
            XCTAssertEqual(consent.value as? String,"0")
            let generate=app.buttons["local-video-generate"]
            reveal(generate);XCTAssertFalse(generate.isEnabled)
            XCTAssertFalse(app.buttons["local-video-download"].isEnabled)
            consent.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
            let enabled=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:generate)
            XCTAssertEqual(XCTWaiter.wait(for:[enabled],timeout:10),.completed)
            XCTAssertEqual(consent.value as? String,"1")
            // Never press Generate: this verifies explicit consent, not speech inference.
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Verified vocals selected; authorization explicit; no generation";shot.lifetime = .keepAlways;add(shot)
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Separate vocals"].waitForExistence(timeout:10))
        }
        for _ in 0..<4 {
            XCTAssertFalse(corrupt.exists)
            app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.72)).press(forDuration:0.01,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.28)))
        }
        XCTAssertFalse(corrupt.exists)
        app.terminate()
    }

}
