import XCTest

@MainActor final class SpeakerHandoffUITests: XCTestCase {
    func testExplicitSavedSpeakerSpeechAndConversionRoutes() {
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES", "-laptopURL", "https://127.0.0.1:9"]
        app.launch()
        let open = app.buttons["local-video-studio"]
        XCTAssertTrue(open.waitForExistence(timeout:25)); open.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout:15))
        func reach(_ element: XCUIElement) {
            for _ in 0..<12 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable, "Expected synthetic fixture control")
        }
        let one = app.buttons["Unidentified speaker one"]
        reach(one); one.tap()
        let speech = app.buttons["local-video-speaker-speech-one"]
        reach(speech); XCTAssertTrue(speech.isEnabled); speech.tap()
        let choice = app.buttons["choose-character"]
        XCTAssertTrue(choice.waitForExistence(timeout:15))
        XCTAssertTrue(choice.label.contains("Synthetic Handoff Alpha"))
        let create = app.buttons["create-character-speech"]
        reach(create); XCTAssertTrue(create.exists)
        XCTAssertFalse(app.buttons["CONVERT"].exists)
        XCTAssertFalse(app.buttons["Stop after current step"].exists)
        let speechShot = XCTAttachment(screenshot:app.screenshot()); speechShot.name="Synthetic Alpha speech destination, no generation"; speechShot.lifetime = .keepAlways; add(speechShot)
        app.navigationBars.buttons.element(boundBy:0).tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout:15))
        let two = app.buttons["Unidentified speaker two"]
        reach(two); two.tap()
        let conversion = app.buttons["local-video-speaker-conversion-two"]
        reach(conversion); XCTAssertTrue(conversion.isEnabled); conversion.tap()
        XCTAssertTrue(choice.waitForExistence(timeout:15))
        XCTAssertTrue(choice.label.contains("Synthetic Handoff Beta"))
        let convert = app.buttons["CONVERT"]
        reach(convert); XCTAssertTrue(convert.exists); XCTAssertFalse(convert.isEnabled)
        XCTAssertFalse(app.buttons["create-character-speech"].exists)
        XCTAssertFalse(app.buttons["Stop after current step"].exists)
        let conversionShot = XCTAttachment(screenshot:app.screenshot()); conversionShot.name="Synthetic Beta conversion destination, no generation"; conversionShot.lifetime = .keepAlways; add(conversionShot)
        app.terminate()
    }
}
