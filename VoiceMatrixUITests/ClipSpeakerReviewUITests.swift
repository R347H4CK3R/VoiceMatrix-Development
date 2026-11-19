import XCTest

/// Runs in a fresh, seeded CI simulator with the genuine licensed speech and
/// pinned on-device diarizer. No synthetic stored analysis or app-specific hooks.
@MainActor final class ClipSpeakerReviewUITests: XCTestCase {
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: upward ? 0.72 : 0.33))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: upward ? 0.33 : 0.72))
            from.press(forDuration: 0.01, thenDragTo: to)
        }
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Full accessibility hierarchy when reveal failed"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element)")
    }

    private func studio(_ app: XCUIApplication) {
        let route = app.buttons["local-video-studio"]
        XCTAssertTrue(route.waitForExistence(timeout: 25))
        reveal(route, in: app)
        route.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout: 15))
    }

    private func enterDuration(_ value: String, app: XCUIApplication) {
        let field = app.textFields["retained-clip-seconds"]
        reveal(field, in: app)
        field.tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + value)
        XCTAssertEqual(field.value as? String, value)
        app.buttons["local-video-keyboard-done"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
    }

    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func prepare(_ app: XCUIApplication) {
        let prepare = app.buttons["retained-clip-prepare-review"]
        let consent = app.switches["retained-clip-authorization"]
        reveal(prepare, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(prepare.isEnabled)
        reveal(consent, in: app, upward: false)
        flip(consent)
        XCTAssertEqual(consent.value as? String, "1")
        reveal(prepare, in: app)
        XCTAssertTrue(prepare.isEnabled)
        prepare.tap()
        XCTAssertTrue(app.navigationBars["Review speaker turns"].waitForExistence(timeout: 35))
    }

    func testReviewRequiresFreshConsentAndKeepsClipSpecificAliasAcrossRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES", "-laptopURL", "https://127.0.0.1:9"]
        app.launch()
        studio(app)

        enterDuration("2.5", app: app)
        let prepConsent = app.switches["retained-clip-authorization"]
        reveal(prepConsent, in: app)
        flip(prepConsent)
        let prepareReview = app.buttons["retained-clip-prepare-review"]
        reveal(prepareReview, in: app)
        XCTAssertFalse(prepareReview.isEnabled, "Under-three-second extraction must not enable speaker review")
        XCTAssertTrue(app.buttons["retained-clip-prepare"].isEnabled, "Existing shorter separation remains available")
        // Avoid scrolling past the form when the duration is just above these buttons.
        reveal(app.textFields["retained-clip-seconds"], in: app, upward: false)
        enterDuration("8", app: app)
        prepare(app)

        let consent = app.switches["clip-speaker-review-authorization"]
        let run = app.buttons["clip-speaker-review-run"]
        let label = app.textFields["clip-speaker-review-label-S1"]
        let alias = app.staticTexts["clip-speaker-review-alias-S1"]
        XCTAssertTrue(consent.waitForExistence(timeout: 15))
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(run.isEnabled)
        XCTAssertFalse(label.exists, "Opening the verified clip did not analyze it")
        reveal(consent, in: app)
        flip(consent)
        XCTAssertTrue(run.isEnabled)
        XCUIDevice.shared.press(.home)
        app.activate()
        let fresh = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "0"), object: consent)
        XCTAssertEqual(XCTWaiter.wait(for: [fresh], timeout: 15), .completed)
        XCTAssertFalse(run.isEnabled)
        XCTAssertFalse(label.exists, "Foreground recovery also must not analyze it")

        flip(consent)
        reveal(run, in: app)
        XCTAssertTrue(run.isEnabled)
        run.tap()
        let status = app.staticTexts["clip-speaker-review-status"]
        let analyzed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Local speaker guesses are ready"), object: status)
        // The form is lazy; wait on status within the initiating section rather
        // than treating an off-screen anonymous-group field as missing evidence.
        XCTAssertEqual(XCTWaiter.wait(for: [analyzed], timeout: 95), .completed, "Expected a real speech turn; last status: \(status.label)")
        XCTAssertFalse(run.exists, "The reviewed result is not a new analysis request")
        reveal(label, in: app)
        label.tap()
        label.typeText("QA narrator\n")
        let save = app.buttons["clip-speaker-review-save-S1"]
        reveal(save, in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
        reveal(alias, in: app, upward: false)
        XCTAssertTrue(alias.label.contains("QA narrator"))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Real speech model guess with a local user label"
        shot.lifetime = .keepAlways
        add(shot)

        app.terminate()
        app.launch()
        studio(app)
        let disclosure = app.buttons["Reopen a prepared clip for speaker review"]
        reveal(disclosure, in: app)
        disclosure.tap()
        let reopened = app.buttons["retained-clip-open-review"]
        reveal(reopened, in: app)
        reopened.tap()
        XCTAssertTrue(app.navigationBars["Review speaker turns"].waitForExistence(timeout: 15))
        reveal(alias, in: app)
        XCTAssertTrue(alias.label.contains("QA narrator"))
        XCTAssertFalse(run.exists, "Reopening reads the saved result without starting analysis")

        app.navigationBars["Review speaker turns"].buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout: 15))
        reveal(app.textFields["retained-clip-seconds"], in: app, upward: false)
        enterDuration("5", app: app)
        prepare(app)
        XCTAssertTrue(consent.waitForExistence(timeout: 15))
        XCTAssertEqual(consent.value as? String, "0")
        XCTAssertFalse(run.isEnabled)
        XCTAssertFalse(alias.exists, "A label for one receipt and analysis is not a label for another clip")
        XCTAssertFalse(label.exists)
        app.terminate()
    }
}
