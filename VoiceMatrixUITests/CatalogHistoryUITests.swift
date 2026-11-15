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
        XCTAssertFalse(app.buttons["Delete retained result"].exists,"Playback must not trigger deletion")
        let stops=app.buttons.matching(identifier:"Stop")
        expectation(for:NSPredicate(format:"count == 2"),evaluatedWith:stops);waitForExpectations(timeout:10)
        // AudioActions exposes the same global Stop in both retained rows.
        // Select the first row, exactly as for Listen / Replay above.
        let stop=stops.element(boundBy:0);reveal(stop,in:app);stop.tap()
        expectation(for:NSPredicate(format:"count == 0"),evaluatedWith:stops);waitForExpectations(timeout:10)
        XCTAssertFalse(app.buttons["Delete retained result"].exists,"Stopping playback must not trigger deletion")
        let saves=app.buttons.matching(identifier:"save-recording");XCTAssertEqual(saves.count,2)
        let save=saves.element(boundBy:0);reveal(save,in:app);save.tap()
        expectation(for:NSPredicate(format:"enabled == false"),evaluatedWith:save);waitForExpectations(timeout:10)
        XCTAssertEqual(save.label,"Saved")
        XCTAssertFalse(app.buttons["Delete retained result"].exists,"Saving first audio must not trigger deletion")
        XCTAssertEqual(stops.count,0,"Saving first audio must not restart playback")
        let secondSave=saves.element(boundBy:1);reveal(secondSave,in:app);XCTAssertTrue(secondSave.isEnabled,"Other attempt with same basename must remain independently saveable");secondSave.tap()
        expectation(for:NSPredicate(format:"enabled == false"),evaluatedWith:secondSave);waitForExpectations(timeout:10);XCTAssertEqual(secondSave.label,"Saved")
        XCTAssertFalse(app.buttons["Delete retained result"].exists,"Saving second audio must not trigger deletion")
        XCTAssertEqual(stops.count,0,"Saving second audio must not restart playback")
        let share=app.buttons.matching(identifier:"Share Audio").element(boundBy:0);reveal(share,in:app);share.tap()
        XCTAssertFalse(app.buttons["Delete retained result"].exists,"Sharing must not trigger deletion")
        XCTAssertEqual(stops.count,0,"Sharing must not restart playback")
        let sharePresented=actionableShareSheet(in:app)
        // Observe both surfaces without activating another app or selecting a recipient.
        for (name,surface) in [("VoiceMatrix",app),("SpringBoard",XCUIApplication(bundleIdentifier:"com.apple.springboard"))] {
            let tree=XCTAttachment(string:surface.debugDescription);tree.name="Share diagnostic "+name+" hierarchy";tree.lifetime = .keepAlways;add(tree)
        }
        let display=XCTAttachment(screenshot:XCUIScreen.main.screenshot());display.name="Share diagnostic full display";display.lifetime = .keepAlways;add(display)
        if !sharePresented {
            // Compare the exact saved copy through the existing Saved screen.
            // Relaunch clears the pending ShareLink interaction, without deleting data.
            app.terminate();app.launchArguments=["-tutorialSeen","YES"];app.launch()
            XCTAssertTrue(app.tabBars.buttons["Saved"].waitForExistence(timeout:30));app.tabBars.buttons["Saved"].tap()
            let recording=app.buttons["speech-A8D5A8AA-2864-4BB3-BF19-AEE5CF424A16"]
            XCTAssertTrue(recording.waitForExistence(timeout:15));reveal(recording,in:app);recording.tap()
            let savedShare=app.buttons["Share"];XCTAssertTrue(savedShare.waitForExistence(timeout:10));reveal(savedShare,in:app);savedShare.tap()
            let savedPresented=actionableShareSheet(in:app)
            let comparison=XCTAttachment(string:"historySharePresented=\(sharePresented); savedCopySharePresented=\(savedPresented)")
            comparison.name="Same-byte sharing comparison";comparison.lifetime = .keepAlways;add(comparison)
            for (name,surface) in [("Saved app",app),("Saved SpringBoard",XCUIApplication(bundleIdentifier:"com.apple.springboard"))] {
                let tree=XCTAttachment(string:surface.debugDescription);tree.name=name;tree.lifetime = .keepAlways;add(tree)
            }
            let screen=XCTAttachment(screenshot:XCUIScreen.main.screenshot());screen.name="Saved copy share display";screen.lifetime = .keepAlways;add(screen)
            XCTAssertTrue(savedPresented,"Control saved recording must expose a genuine export action")
        }
        XCTAssertTrue(sharePresented,"System share sheet must expose a real export action; no external destination selected")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Retained unverified audio system sharing";shot.lifetime = .keepAlways;add(shot)
        app.terminate();app.launchArguments=["-tutorialSeen","YES"];app.launch();openHistory()
        let remove=app.buttons.matching(identifier:"Delete this retained result").element(boundBy:0);reveal(remove,in:app);remove.tap()
        let confirm=app.buttons["Delete retained result"];XCTAssertTrue(confirm.waitForExistence(timeout:10))
        let cancel=app.buttons["Cancel"]
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else {
            // iOS popover confirmation omits a Cancel row and exposes this dismiss region.
            let dismiss=app.otherElements["PopoverDismissRegion"];XCTAssertTrue(dismiss.exists && dismiss.isHittable);dismiss.tap()
        }
        XCTAssertTrue(confirm.waitForNonExistence(timeout:10))
        XCTAssertTrue(remove.exists,"Cancel/dismiss must retain the history item")
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
    private func actionableShareSheet(in app:XCUIApplication)->Bool {
        let sheet=app.otherElements["ActivityListView"]
        guard sheet.waitForExistence(timeout:10) else { return false }
        // Actual iOS26 AX exposes export actions as Cells, not Buttons.
        for label in ["Save to Files","Copy"] {
            let action=sheet.cells.matching(NSPredicate(format:"label == %@",label)).firstMatch
            if action.waitForExistence(timeout:5) && action.isHittable { return true }
        }
        return false
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
