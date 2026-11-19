import XCTest
@testable import VoiceMatrix

@MainActor
final class MKVPythonRuntimeTests: XCTestCase {
    private let job = "00000000-0000-4000-8000-000000000001"
    private let attempt = "00000000-0000-4000-8000-000000000002"

    private func runtime() -> VMPythonRuntime {
        let provider = VMWebKitChallengeProvider()
        return VMPythonRuntime(javaScriptEvaluator: { script, input, identity, completion in
            provider.evaluateScript(script, inputJSON: input, requestID: identity) { result, error in
                completion(result, error)
            }
        }, canceller: { identity in provider.cancelRequest(identity) })
    }

    private func request(_ stage: String) throws -> String {
        let a = String(repeating: "a", count: 64)
        let m = String(repeating: "b", count: 64)
        let d = String(repeating: "c", count: 64)
        let mkv: [String: String] = ["jobID": job, "attemptID": attempt, "acquisitionSHA256": a, "mkvSHA256": m]
        let derived: [String: String] = ["jobID": job, "attemptID": attempt, "mkvSHA256": m, "movSHA256": d]
        let value: [String: Any] = [
            "schemaVersion": 1, "jobID": job, "attemptID": attempt, "stage": stage, "acquisitionSHA256": a,
            "mkv": stage == "acquisition" ? NSNull() as Any : mkv,
            "derived": stage == "derivedVerified" ? derived as Any : NSNull()
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    private func object(_ result: String?) throws -> [String: Any] {
        let text = try XCTUnwrap(result)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    func testBundledPolicyExecutesAllThreeDecisions() async throws {
        let runtime = runtime()
        for (stage, action) in [("acquisition", "prepare"), ("mkvVerified", "derive"),
                                ("derivedVerified", "complete")] {
            let finished = expectation(description: action)
            let input = try request(stage)
            _ = runtime.decideMKVStageJSON(input) { result, error in
                XCTAssertNil(error)
                do {
                    let payload = try self.object(result)
                    XCTAssertEqual(payload["schemaVersion"] as? Int, 1)
                    XCTAssertEqual(payload["jobID"] as? String, self.job)
                    XCTAssertEqual(payload["attemptID"] as? String, self.attempt)
                    XCTAssertEqual(payload["stage"] as? String, stage)
                    XCTAssertEqual(payload["action"] as? String, action)
                } catch { XCTFail("Expected bundled Python decision: \(error)") }
                finished.fulfill()
            }
            await fulfillment(of: [finished], timeout: 20)
        }
    }

    func testEmbeddedNULRejectsAndOversizeNeverReturnsDecision() async throws {
        let runtime = runtime()
        let rejected = expectation(description: "embedded NUL received by Python")
        _ = runtime.decideMKVStageJSON(try request("acquisition") + "\0") { result, error in
            XCTAssertNil(error)
            XCTAssertEqual(result, #"{"schemaVersion":1,"action":"reject"}"#)
            rejected.fulfill()
        }
        let bounded = expectation(description: "wrapper rejects oversize")
        _ = runtime.decideMKVStageJSON(String(repeating: "é", count: 2049)) { result, error in
            XCTAssertNil(result)
            XCTAssertNotNil(error)
            bounded.fulfill()
        }
        await fulfillment(of: [rejected, bounded], timeout: 20)
    }

    func testCancellationSuppressesDecisionWithoutAffectingNextRequest() async throws {
        let runtime = runtime()
        let cancelled = expectation(description: "cancelled response only")
        cancelled.assertForOverFulfill = true
        let next = expectation(description: "next decision")
        next.assertForOverFulfill = true
        let input = try request("acquisition")
        let firstIdentity = runtime.decideMKVStageJSON(input) { result, error in
            XCTAssertNil(result)
            XCTAssertNotNil(error)
            cancelled.fulfill()
        }
        runtime.cancelRequest(firstIdentity)
        let secondIdentity = runtime.decideMKVStageJSON(input) { result, error in
            XCTAssertNil(error)
            XCTAssertEqual((try? self.object(result))?["action"] as? String, "prepare")
            next.fulfill()
        }
        XCTAssertNotEqual(firstIdentity, secondIdentity)
        await fulfillment(of: [cancelled, next], timeout: 20, enforceOrder: true)
        // Drain the same serialized worker again before leaving the test.
        let drained = expectation(description: "serialized worker drained")
        _ = runtime.decideMKVStageJSON(input) { _, _ in drained.fulfill() }
        await fulfillment(of: [drained], timeout: 20)
    }

    func testOriginalResolverStillExecutesBundledAuthorizationDecision() async {
        let finished = expectation(description: "original Python route")
        let runtime = runtime()
        _ = runtime.resolveJSON(#"{"schemaVersion":1,"authorized":false}"#) { result, error in
            XCTAssertNil(error)
            let payload = try? self.object(result)
            XCTAssertEqual(payload?["status"] as? String, "unavailable")
            XCTAssertEqual(payload?["error_code"] as? String, "authorization_required")
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 20)
    }
}
