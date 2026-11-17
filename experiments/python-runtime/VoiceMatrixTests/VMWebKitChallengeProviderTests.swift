import XCTest
@testable import VoiceMatrix

@available(iOS 15.0, *)
@MainActor
final class VMWebKitChallengeProviderTests: XCTestCase {
    private func evaluate(_ provider: VMWebKitChallengeProvider, _ script: String, input: String = "{}") async -> (String?, NSError?) {
        await withCheckedContinuation { continuation in
            provider.evaluateScript(script, inputJSON: input) { result, error in
                continuation.resume(returning: (result, error))
            }
        }
    }
    func testJSONRoundTripAndNoPersistentGlobal() async {
        let provider = VMWebKitChallengeProvider()
        let first = await evaluate(provider, "globalThis.secret = 42; return {answer: input.x + 1};", input: "{\"x\":41}")
        XCTAssertNil(first.1); XCTAssertEqual(first.0, "{\"answer\":42}")
        let second = await evaluate(provider, "return typeof globalThis.secret;")
        XCTAssertNil(second.1); XCTAssertEqual(second.0, "\"undefined\"")
    }
    func testValidationAndExceptions() async {
        let provider = VMWebKitChallengeProvider()
        let badJSON = await evaluate(provider, "return 1", input: "not json")
        XCTAssertNotNil(badJSON.1)
        let oversized = await evaluate(provider, String(repeating: " ", count: VMWebKitChallengeProvider.maxScriptBytes + 1))
        XCTAssertNotNil(oversized.1)
        let exception = await evaluate(provider, "throw new Error('private token')")
        XCTAssertNotNil(exception.1)
        XCTAssertFalse(exception.1!.localizedDescription.contains("private token"))
        let tooLarge = await evaluate(provider, "return 'x'.repeat(1048577)")
        XCTAssertNotNil(tooLarge.1)
    }
    func testNetworkAndPopupDenied() async {
        let provider = VMWebKitChallengeProvider()
        let result = await evaluate(provider, """
        let denied = false;
        try { await fetch('https://example.com/'); } catch (_) { denied = true; }
        return {denied, popup: window.open('https://example.com/') === null};
        """)
        XCTAssertNil(result.1)
        XCTAssertEqual(result.0, "{\"denied\":true,\"popup\":true}")
    }
    func testSingleFlightCancellationAndQuarantine() async {
        let provider = VMWebKitChallengeProvider()
        let done = expectation(description: "cancelled exactly once")
        done.assertForOverFulfill = true
        provider.evaluateScript("await new Promise(() => {});", inputJSON: "{}") { result, error in
            XCTAssertNil(result); XCTAssertNotNil(error); done.fulfill()
        }
        let busy = await evaluate(provider, "return true")
        XCTAssertNotNil(busy.1)
        provider.cancelAll()
        await fulfillment(of: [done], timeout: 2)
        let quarantined = await evaluate(provider, "return true")
        XCTAssertNotNil(quarantined.1)
    }
    func testNonFiniteAndCyclicResultsFail() async {
        for script in ["return NaN", "return Infinity", "return {n:-Infinity}", "const x={}; x.x=x; return x"] {
            let result = await evaluate(VMWebKitChallengeProvider(), script)
            XCTAssertNil(result.0); XCTAssertNotNil(result.1)
        }
    }
    func testOwnerReleaseStillCompletesOnce() async {
        var provider: VMWebKitChallengeProvider? = VMWebKitChallengeProvider()
        weak var owner = provider
        let done = expectation(description: "retained through completion")
        done.assertForOverFulfill = true
        provider?.evaluateScript("return 42", inputJSON: "{}", requestID: "owner") { result, error in
            XCTAssertEqual(result, "42"); XCTAssertNil(error); done.fulfill()
        }
        provider = nil
        XCTAssertNotNil(owner)
        await fulfillment(of: [done], timeout: 25)
        // Allow the completion stack to unwind before checking cycle removal.
        await Task.yield()
        XCTAssertNil(owner)
    }
    func testStaleCancellationCannotCancelNewRequest() async {
        let provider = VMWebKitChallengeProvider()
        let previous = await evaluate(provider, "return 1")
        XCTAssertNil(previous.1)
        let done = expectation(description: "new request unaffected")
        done.assertForOverFulfill = true
        provider.evaluateScript("return 2", inputJSON: "{}", requestID: "new") { result, error in
            XCTAssertEqual(result, "2"); XCTAssertNil(error); done.fulfill()
        }
        provider.cancelRequest("old")
        await fulfillment(of: [done], timeout: 25)
    }
    func testRequestCancellationCompletesExactlyOnce() async {
        let provider = VMWebKitChallengeProvider()
        let done = expectation(description: "request cancelled")
        done.assertForOverFulfill = true
        provider.evaluateScript("await new Promise(() => {})", inputJSON: "{}", requestID: "cancel") { result, error in
            XCTAssertNil(result); XCTAssertNotNil(error); done.fulfill()
        }
        provider.cancelRequest("cancel")
        provider.cancelRequest("cancel")
        await fulfillment(of: [done], timeout: 2)
    }
    func testNavigationCannotReplaceCalculationDocument() async {
        let result = await evaluate(VMWebKitChallengeProvider(), """
        location.href = 'https://example.com/navigation-test';
        await new Promise(resolve => setTimeout(resolve, 100));
        return location.href;
        """)
        XCTAssertNil(result.1); XCTAssertEqual(result.0, "\"about:blank\"")
        // This assertion is NOT proof that no request left the device; use controlled server logs.
    }
    func testCompletionCanReentrantlyStartNextJob() async {
        let provider = VMWebKitChallengeProvider()
        let done = expectation(description: "reentrant completion")
        done.assertForOverFulfill = true
        provider.evaluateScript("return 1", inputJSON: "{}", requestID: "first") { first, firstError in
            XCTAssertEqual(first, "1"); XCTAssertNil(firstError)
            provider.evaluateScript("return 2", inputJSON: "{}", requestID: "second") { second, secondError in
                XCTAssertEqual(second, "2"); XCTAssertNil(secondError); done.fulfill()
            }
            provider.cancelRequest("first")
        }
        await fulfillment(of: [done], timeout: 25)
    }
    func testDeadlineResolvesAndQuarantines() async {
        let provider = VMWebKitChallengeProvider()
        let start = Date()
        let result = await evaluate(provider, "await new Promise(() => {});")
        XCTAssertNil(result.0); XCTAssertNotNil(result.1)
        XCTAssertLessThan(Date().timeIntervalSince(start), 25)
        let later = await evaluate(provider, "return 1")
        XCTAssertNotNil(later.1)
    }
}
