import Foundation
#if os(iOS)

/// Only the application-owned native engine can start Python. Tests inject a local fake.
@MainActor
protocol OnDeviceResolverEngine: AnyObject {
    func start(_ request: String, completion: @escaping (String?, Error?) -> Void) -> String
    func cancelRequest(_ identity: String)
}

@MainActor
final class OnDeviceYouTubeResolver {
    static let shared = OnDeviceYouTubeResolver(engine: NativeEngine())
    private let engine: OnDeviceResolverEngine
    init(engine: OnDeviceResolverEngine) { self.engine = engine }

    func resolve(_ input: URL, authorized: Bool, timeout: TimeInterval = 100) async throws -> [LocalMediaURLPolicy.Part] {
        try Task.checkCancellation()
        guard authorized else { throw LocalMediaURLPolicy.Failure.restricted }
        let normalized = try LocalMediaURLPolicy.input(input.absoluteString)
        _ = try LocalMediaURLPolicy.videoID(normalized)
        let request = try JSONEncoder().encode(Request(schemaVersion: 1, url: normalized.absoluteString, authorized: true))
        guard request.count <= 16_384, let text = String(data: request, encoding: .utf8) else { throw LocalMediaURLPolicy.Failure.bounds }
        let engine = self.engine
        let state = Pending { identity in
            Task { @MainActor in engine.cancelRequest(identity) }
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                guard state.install(continuation) else { return }
                state.launch {
                    engine.start(text) { response, error in
                        do {
                            guard error == nil, let response else { throw LocalMediaURLPolicy.Failure.resolverUnavailable }
                            state.finish(.success(try Self.decode(response)))
                        } catch { state.finish(.failure(error)) }
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, timeout)) {
                    state.abort(LocalMediaURLPolicy.Failure.bounds)
                }
            }
        } onCancel: { state.abort(CancellationError()) }
    }

    /// Revalidate Python output; never trust it as a URL/download policy exemption.
    static func decode(_ text: String) throws -> [LocalMediaURLPolicy.Part] {
        guard text.utf8.count <= 1_048_576, let bytes = text.data(using: .utf8) else { throw LocalMediaURLPolicy.Failure.bounds }
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: bytes) }
        catch { throw LocalMediaURLPolicy.Failure.response }
        guard response.schemaVersion == 1 else { throw LocalMediaURLPolicy.Failure.response }
        guard response.status == "ready" else {
            switch response.error_code {
            case "cancelled": throw CancellationError()
            case "restricted", "authorization_required": throw LocalMediaURLPolicy.Failure.restricted
            case "no_supported_media": throw LocalMediaURLPolicy.Failure.noDirectStreams
            case "duration_limit", "response_limit", "request_limit", "redirect_limit", "timeout": throw LocalMediaURLPolicy.Failure.bounds
            case "network_unavailable": throw LocalMediaURLPolicy.Failure.resolverNetwork
            case "source_unavailable": throw LocalMediaURLPolicy.Failure.resolverSource
            default: throw LocalMediaURLPolicy.Failure.resolverUnavailable
            }
        }
        guard let parts = response.parts, (1...2).contains(parts.count) else { throw LocalMediaURLPolicy.Failure.response }
        if parts.count == 1 {
            guard parts[0].kind == .combined, parts[0].ext == "mp4" else { throw LocalMediaURLPolicy.Failure.unsupported }
        } else {
            guard parts[0].kind == .video, parts[0].ext == "mp4", parts[1].kind == .audio, parts[1].ext == "m4a" else { throw LocalMediaURLPolicy.Failure.unsupported }
        }
        var total: Int64 = 0
        for part in parts {
            try LocalMediaURLPolicy.validate(part.url, role: .stream)
            guard part.bytes > 0, part.bytes <= LocalMediaURLPolicy.maximumBytes else { throw LocalMediaURLPolicy.Failure.bounds }
            let (sum, overflow) = total.addingReportingOverflow(part.bytes)
            guard !overflow, sum <= LocalMediaURLPolicy.maximumBytes else { throw LocalMediaURLPolicy.Failure.bounds }
            total = sum
        }
        return parts.map { .init(url: $0.url, kind: $0.kind, ext: $0.ext) }
    }

    private struct Request: Encodable { let schemaVersion: Int; let url: String; let authorized: Bool }
    private struct Response: Decodable {
        let schemaVersion: Int
        let status: String
        let parts: [Part]?
        let error_code: String?
    }
    private struct Part: Decodable { let url: URL; let kind: LocalMediaURLPolicy.Kind; let ext: String; let bytes: Int64 }

    /// Continuation and request identity races are protected together. A late callback
    /// cannot resume twice or cancel a subsequent unrelated native request.
    private final class Pending: @unchecked Sendable {
        private let lock = NSRecursiveLock()
        private var continuation: CheckedContinuation<[LocalMediaURLPolicy.Part], Error>?
        private var identity: String?
        private var finished = false
        private var aborted: Error?
        private let cancel: @Sendable (String) -> Void
        init(cancel: @escaping @Sendable (String) -> Void) { self.cancel = cancel }
        func install(_ value: CheckedContinuation<[LocalMediaURLPolicy.Part], Error>) -> Bool {
            lock.lock()
            if finished { let error = aborted ?? CancellationError(); lock.unlock(); value.resume(throwing: error); return false }
            continuation = value
            lock.unlock()
            return true
        }
        func launch(_ start: () -> String) {
            // Admission and nonblocking native enqueue are one linearization point.
            // Recursive locking permits a test engine's synchronous completion.
            lock.lock(); defer { lock.unlock() }
            guard !finished else { return }
            identity = start()
        }
        func finish(_ result: Result<[LocalMediaURLPolicy.Part], Error>) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true; let pending = continuation; continuation = nil; lock.unlock()
            pending?.resume(with: result)
        }
        func abort(_ error: Error) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true; aborted = error; let pending = continuation; continuation = nil; let current = identity; lock.unlock()
            if let current { cancel(current) }
            pending?.resume(throwing: error)
        }
    }

    @MainActor
    private final class NativeEngine: OnDeviceResolverEngine {
        private let provider: VMWebKitChallengeProvider
        private let runtime: VMPythonRuntime
        init() {
            let provider = VMWebKitChallengeProvider()
            self.provider = provider
            runtime = VMPythonRuntime(javaScriptEvaluator: { script, input, identity, completion in
                provider.evaluateScript(script, inputJSON: input, requestID: identity) { result, error in completion(result, error) }
            }, canceller: { identity in provider.cancelRequest(identity) })
        }
        func start(_ request: String, completion: @escaping (String?, Error?) -> Void) -> String {
            runtime.resolveJSON(request) { result, error in completion(result, error) }
        }
        func cancelRequest(_ identity: String) { runtime.cancelRequest(identity) }
    }
}

#endif
