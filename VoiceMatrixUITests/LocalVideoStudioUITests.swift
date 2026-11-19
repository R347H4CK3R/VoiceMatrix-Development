import XCTest
import UIKit
@MainActor final class LocalVideoStudioUITests: XCTestCase {
    func testHomeVideoLinkErrorKeepsInputAndStartsNoJob() {
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES"]
        app.launch()
        let hero = app.buttons["local-video-studio"]
        XCTAssertTrue(hero.waitForExistence(timeout: 25))
        XCTAssertGreaterThanOrEqual(hero.frame.height, 44)
        hero.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout: 15))
        func reveal(_ element: XCUIElement) {
            for _ in 0..<10 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.exists && element.isHittable)
        }
        let choose = app.buttons["local-video-import"]
        reveal(choose)
        XCTAssertGreaterThanOrEqual(choose.frame.height, 44)
        let field = app.textFields["local-video-url"]
        reveal(field)
        XCTAssertEqual(field.label, "Video link")
        XCTAssertGreaterThanOrEqual(field.frame.height, 44)
        let invalid = "not-a-video-link"
        field.tap()
        field.typeText(invalid)
        app.buttons["Done"].tap()
        let paste = app.buttons["local-video-paste"]
        reveal(paste)
        XCTAssertGreaterThanOrEqual(paste.frame.height, 44)
        let permission = app.switches["local-video-authorization"]
        reveal(permission)
        XCTAssertEqual(permission.value as? String, "0")
        let download = app.buttons["local-video-download"]
        XCTAssertFalse(download.isEnabled)
        permission.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        reveal(download)
        XCTAssertGreaterThanOrEqual(download.frame.height, 44)
        XCTAssertTrue(download.isEnabled)
        download.tap()
        let status = app.staticTexts["local-video-status"]
        let rejected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "Use an HTTPS YouTube link or a direct media link"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [rejected], timeout: 15), .completed)
        XCTAssertEqual(field.value as? String, invalid, "Rejected input must remain available to edit")
        XCTAssertFalse(app.buttons["local-video-generate"].isEnabled)
        let details = app.buttons["Processing details"]
        reveal(details)
        details.tap()
        XCTAssertTrue(app.staticTexts["No local job has started."].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Direct Home bad link, corrective error, no job"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testFriendlyStudioAtAccessibilityTextSizeDoesNotStartWork() {
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-laptopURL", "https://127.0.0.1:9"]
        app.launch()
        let hero = app.buttons["local-video-studio"]
        XCTAssertTrue(hero.waitForExistence(timeout: 25))
        for _ in 0..<5 where !hero.isHittable { app.swipeUp() }
        XCTAssertTrue(hero.isHittable)
        hero.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout: 15))
        let steps = app.descendants(matching: .any).matching(identifier: "video-studio-steps").firstMatch
        for _ in 0..<5 where !steps.isHittable { app.swipeUp() }
        XCTAssertTrue(steps.exists)
        XCTAssertGreaterThanOrEqual(steps.frame.minX, 0)
        XCTAssertLessThanOrEqual(steps.frame.maxX, app.frame.width)
        let guidance = XCTAttachment(screenshot: app.screenshot())
        guidance.name = "Three steps at largest accessibility text"
        guidance.lifetime = .keepAlways
        add(guidance)
        let choose = app.buttons["local-video-import"]
        for _ in 0..<10 where !choose.isHittable { app.swipeUp() }
        XCTAssertTrue(choose.isHittable)
        XCTAssertGreaterThanOrEqual(choose.frame.height, 44)
        let permission = app.switches["local-video-authorization"]
        for _ in 0..<10 where !permission.isHittable { app.swipeUp() }
        XCTAssertTrue(permission.isHittable)
        XCTAssertEqual(permission.value as? String, "0")
        let create = app.buttons["local-video-generate"]
        for _ in 0..<5 where !create.isHittable { app.swipeUp() }
        XCTAssertFalse(create.isEnabled)
        XCTAssertFalse(app.buttons["local-video-download"].isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Friendly studio largest accessibility text, permission required"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testLegacyLaptopLogOffersStandaloneRecoveryWithoutStartingWork() {
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES", "-laptopURL", "https://127.0.0.1:9"]
        app.launch()
        let optional = app.buttons["Optional laptop tools"]
        for _ in 0..<8 where !optional.isHittable { app.swipeUp() }
        XCTAssertTrue(optional.waitForExistence(timeout: 10)); optional.tap()
        let list = app.buttons["saved-video-list"]
        for _ in 0..<5 where !list.isHittable { app.swipeUp() }
        XCTAssertTrue(list.exists); list.tap()
        let log = app.buttons["live-video-workflow"]
        for _ in 0..<10 where !log.isHittable { app.swipeUp() }
        XCTAssertTrue(log.exists); log.tap()
        let recover = app.buttons["workflow-on-iphone-recovery"]
        XCTAssertTrue(recover.waitForExistence(timeout: 15)); recover.tap()
        XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["local-video-import"].exists)
        XCTAssertFalse(app.buttons["local-video-download"].isEnabled)
        XCTAssertFalse(app.buttons["local-video-generate"].isEnabled)
        app.navigationBars["Video Voice Studio"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["workflow-on-iphone-recovery"].waitForExistence(timeout: 10))
    }

    func testExplicitPasteStagesURLWithoutStartingDownloadAndRejectsOversize() {
        UIPasteboard.general.string = "https://youtu.be/AAAAAAAAAAA"
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES", "-laptopURL", "https://127.0.0.1:9"]
        app.launch()
        let open=app.buttons["local-video-studio"]
        XCTAssertTrue(open.waitForExistence(timeout:25));open.tap()
        let paste=app.buttons["local-video-paste"]
        XCTAssertTrue(paste.waitForExistence(timeout:15))
        for _ in 0..<4 where !paste.isHittable { app.swipeUp() }
        paste.tap()
        let field=app.textFields["local-video-url"]
        let staged=NSPredicate(format:"value == %@", "https://www.youtube.com/watch?v=AAAAAAAAAAA")
        expectation(for:staged,evaluatedWith:field)
        waitForExpectations(timeout:10)
        XCTAssertFalse(app.buttons["local-video-download"].isEnabled)
        UIPasteboard.general.string = String(repeating:"x",count:16_385)
        paste.tap()
        XCTAssertTrue(app.staticTexts["Clipboard must contain one supported video URL of at most 16,384 bytes."].waitForExistence(timeout:10))
        XCTAssertEqual(field.value as? String,"https://www.youtube.com/watch?v=AAAAAAAAAAA")
        XCTAssertFalse(app.buttons["local-video-download"].isEnabled)
    }

    func testStandaloneScreenCanReopenWithoutLaptopAndCannotGenerateWithoutMedia() {
        let app = XCUIApplication()
        app.launchArguments = ["-tutorialSeen", "YES", "-laptopURL", "https://127.0.0.1:9"]
        app.launch()
        for _ in 0..<2 {
            let open = app.buttons["local-video-studio"]
            XCTAssertTrue(open.waitForExistence(timeout: 25)); open.tap()
            XCTAssertTrue(app.navigationBars["Video Voice Studio"].waitForExistence(timeout: 15))
            let generate = app.buttons["local-video-generate"]
            for _ in 0..<5 where !generate.isHittable { app.swipeUp() }
            XCTAssertFalse(generate.isEnabled)
            XCTAssertTrue(app.buttons["local-video-import"].exists)
            XCTAssertTrue(app.buttons["local-video-paste"].exists)
            let details = app.buttons["Processing details"]
            for _ in 0..<8 where !details.isHittable { app.swipeUp() }
            XCTAssertTrue(details.exists)
            XCTAssertFalse(app.staticTexts["No local job has started."].exists)
            details.tap()
            XCTAssertTrue(app.staticTexts["No local job has started."].waitForExistence(timeout: 10))
            let log = app.descendants(matching: .any).matching(identifier: "local-video-live-log").firstMatch
            for _ in 0..<8 where !log.isHittable { app.swipeUp() }
            XCTAssertTrue(log.exists)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "Standalone empty state and truthful live log"
            capture.lifetime = .keepAlways; add(capture)
            app.navigationBars["Video Voice Studio"].buttons.element(boundBy: 0).tap()
        }
    }
}
