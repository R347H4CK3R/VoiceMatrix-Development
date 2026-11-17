import XCTest
@testable import VoiceMatrix

@MainActor
final class OnDeviceMediaResolverTests: XCTestCase {
    private let source = URL(string: "https://youtu.be/abcdefghijk")!
    private var ready: String { #"{"schemaVersion":1,"status":"ready","parts":[{"url":"https://rr1.googlevideo.com/video?sig=private-test-token","kind":"combined","ext":"mp4","bytes":1000}]}"# }
    private final class Engine: OnDeviceResolverEngine {
        var requests: [String] = []
        var cancellations: [String] = []
        var reply: ((String?, Error?) -> Void)?
        func start(_ request: String, completion: @escaping (String?, Error?) -> Void) -> String {
            requests.append(request); reply = completion; return "request-\(requests.count)"
        }
        func cancelRequest(_ identity: String) { cancellations.append(identity) }
    }
    func testBoundedNativePlanAndInvalidResponses() throws {
        let plan = try OnDeviceYouTubeResolver.decode(ready)
        XCTAssertEqual(plan.count, 1); XCTAssertEqual(plan[0].kind, .combined)
        for bad in [ready.replacingOccurrences(of: "rr1.googlevideo.com", with: "evil.test"),
                    ready.replacingOccurrences(of: "https://", with: "http://"),
                    ready.replacingOccurrences(of: "\"bytes\":1000", with: "\"bytes\":0"),
                    ready.replacingOccurrences(of: "\"bytes\":1000", with: "\"bytes\":536870913"),
                    ready.replacingOccurrences(of: "\"kind\":\"combined\"", with: "\"kind\":\"audio\""),
                    ready.replacingOccurrences(of: "\"schemaVersion\":1", with: "\"schemaVersion\":2"), "not JSON"] {
            XCTAssertThrowsError(try OnDeviceYouTubeResolver.decode(bad))
        }
    }
    func testResolverDiagnosticsUseFixedAllowlistedMappings() throws {
        for (code, expectedTag) in [("network_unavailable", "[resolver-network]"), ("source_unavailable", "[resolver-source]"), ("engine_unavailable", "[resolver-engine]"), ("PRIVATE_UPSTREAM_DETAIL", "[resolver-engine]")] {
            let payload: [String: Any] = ["schemaVersion": 1, "status": "unavailable", "error_code": code,
                                          "message": "PRIVATE_PROVIDER_BODY https://example.invalid/?token=PRIVATE_TEST_TOKEN"]
            let text = String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
            do { _ = try OnDeviceYouTubeResolver.decode(text); XCTFail("Failure response returned a plan") }
            catch {
                XCTAssertTrue(error.localizedDescription.contains(expectedTag))
                XCTAssertFalse(error.localizedDescription.contains("PRIVATE_"))
                XCTAssertFalse(error.localizedDescription.contains("example.invalid"))
                XCTAssertFalse(error.localizedDescription.contains("token="))
            }
        }
    }
    func testFailureMessagesNeverEchoUpstreamDetails() {
        do {
            _ = try OnDeviceYouTubeResolver.decode(#"{"schemaVersion":1,"status":"unavailable","error_code":"private-url-secret"}"#)
            XCTFail("Unknown failure accepted")
        } catch { XCTAssertFalse(error.localizedDescription.contains("private-url-secret")) }
    }
    func testSuccessUsesCanonicalAuthorizedRequest() async throws {
        let engine = Engine(); let resolver = OnDeviceYouTubeResolver(engine: engine)
        let task = Task { try await resolver.resolve(source, authorized: true) }
        while engine.reply == nil { await Task.yield() }
        let request = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(engine.requests[0].utf8)) as? [String: Any])
        XCTAssertEqual(request["url"] as? String, "https://www.youtube.com/watch?v=abcdefghijk")
        XCTAssertEqual(request["authorized"] as? Bool, true)
        engine.reply?(ready, nil)
        let result = try await task.value; XCTAssertEqual(result.count, 1)
        XCTAssertTrue(engine.cancellations.isEmpty)
    }
    func testCancellationDiscardsLateReplyAndDoesNotCancelNextRequest() async throws {
        let engine = Engine(); let resolver = OnDeviceYouTubeResolver(engine: engine)
        let first = Task { try await resolver.resolve(source, authorized: true) }
        while engine.reply == nil { await Task.yield() }
        let oldReply = engine.reply
        first.cancel()
        do { _ = try await first.value; XCTFail("Cancellation returned a plan") }
        catch is CancellationError { } catch { XCTFail("Wrong error") }
        while engine.cancellations.isEmpty { await Task.yield() }
        XCTAssertEqual(engine.cancellations, ["request-1"])
        engine.reply = nil
        let second = Task { try await resolver.resolve(source, authorized: true) }
        while engine.reply == nil { await Task.yield() }
        oldReply?(ready, nil)
        engine.reply?(ready, nil)
        let result = try await second.value; XCTAssertEqual(result.count, 1)
        XCTAssertEqual(engine.cancellations, ["request-1"])
    }
    func testTimeoutCancelsTheCorrectNativeRequest() async {
        let engine = Engine(); let resolver = OnDeviceYouTubeResolver(engine: engine)
        do { _ = try await resolver.resolve(source, authorized: true, timeout: 0.01); XCTFail("Timeout accepted") }
        catch LocalMediaURLPolicy.Failure.bounds { } catch { XCTFail("Wrong error") }
        while engine.cancellations.isEmpty { await Task.yield() }
        XCTAssertEqual(engine.cancellations, ["request-1"])
    }
    func testUnauthorizedOrAlreadyCancelledNeverStartsRuntime() async {
        let engine = Engine(); let resolver = OnDeviceYouTubeResolver(engine: engine)
        do { _ = try await resolver.resolve(source, authorized: false); XCTFail("Authorization missing") } catch { }
        let task = Task { try await resolver.resolve(source, authorized: true) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation ignored") } catch { }
        XCTAssertTrue(engine.requests.isEmpty)
    }
}
