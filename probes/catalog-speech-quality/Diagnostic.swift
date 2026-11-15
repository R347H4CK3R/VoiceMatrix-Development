import Foundation
import CryptoKit

@main struct CatalogQualityDiagnostic {
    enum Failure: Error { case assertion }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.assertion }
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        let base = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL
        let storeRoot = base.appendingPathComponent("history", isDirectory: true)
        let quality = CatalogSpeechQuality(root: storeRoot, asrBundle: resources.appendingPathComponent("ParakeetASR"))
        let text = "Please close the window and bring the notebook."
        let identity = CatalogSpeechQuality.Identity(voiceID: "diagnostic", referenceHash: String(repeating: "a", count: 64), requestedText: text, controls: "default", created: Date())
        @MainActor func copy(_ name: String, using store: CatalogSpeechQuality) throws -> URL {
            let file = try store.destination(identity: identity)
            try FileManager.default.copyItem(at: base.appendingPathComponent(name + ".wav"), to: file)
            return file
        }
        let passed = try copy("passed", using: quality)
        let pass = try await quality.check(passed, expected: text)
        guard pass.verified, pass.wordErrorRate == 0 else { throw Failure.assertion }
        let rejected = try copy("failed", using: quality)
        let fail = try await quality.check(rejected, expected: text)
        guard !fail.verified, fail.wordErrorRate == 0.125 else { throw Failure.assertion }
        let long = try copy("long", using: quality)
        let unsupported = try await quality.check(long, expected: text)
        guard !unsupported.verified, unsupported.recognizedText == nil else { throw Failure.assertion }
        let canceled = try copy("passed", using: quality)
        let task = Task { @MainActor in try await quality.check(canceled, expected: text) }
        task.cancel()
        do { _ = try await task.value; throw Failure.assertion } catch is CancellationError { }
        let canceledResult = try JSONDecoder().decode(CatalogSpeechQuality.Result.self, from: Data(contentsOf: canceled.deletingLastPathComponent().appendingPathComponent("word-check.json")))
        guard !canceledResult.verified else { throw Failure.assertion }
        let unavailable = CatalogSpeechQuality(root: storeRoot, asrBundle: base.appendingPathComponent("missing-model"))
        let missing = try copy("passed", using: unavailable)
        let absent = try await unavailable.check(missing, expected: text)
        guard !absent.verified else { throw Failure.assertion }
        let reloaded = CatalogSpeechQuality(root: storeRoot, asrBundle: nil)
        let history = try reloaded.history()
        guard history.count == 5, history.allSatisfy({ !$0.verified && $0.identity.voiceID == identity.voiceID && $0.identity.referenceHash == identity.referenceHash }),
              try Data(contentsOf: passed) == Data(contentsOf: base.appendingPathComponent("passed.wav")),
              try Data(contentsOf: rejected) == Data(contentsOf: base.appendingPathComponent("failed.wav")),
              try Data(contentsOf: long) == Data(contentsOf: base.appendingPathComponent("long.wav")) else { throw Failure.assertion }
        let empty = try reloaded.destination(identity: identity)
        guard let emptyID = UUID(uuidString: empty.deletingLastPathComponent().lastPathComponent),
              try reloaded.history().contains(where: { $0.id == emptyID && $0.audio == nil }) else { throw Failure.assertion }
        try FileManager.default.removeItem(at: empty.deletingLastPathComponent().appendingPathComponent("request.json"))
        guard try reloaded.history().contains(where: { $0.id == emptyID && $0.audio == nil && $0.identity.referenceHash == "unknown" }) else { throw Failure.assertion }
        let rawOnly = empty.deletingPathExtension().appendingPathExtension("raw.wav")
        try FileManager.default.copyItem(at: base.appendingPathComponent("failed.wav"), to: rawOnly)
        guard try reloaded.history().contains(where: { $0.id == emptyID && $0.audio == rawOnly && !$0.verified }) else { throw Failure.assertion }
        try reloaded.remove(emptyID)
        // Synthetic sparse storage fixture only, never a user recording.
        let oversized = try reloaded.destination(identity: identity)
        FileManager.default.createFile(atPath: oversized.path, contents: nil)
        let handle = try FileHandle(forWritingTo: oversized)
        try handle.truncate(atOffset: 257 * 1024 * 1024); try handle.close()
        do { _ = try reloaded.destination(identity: identity); throw Failure.assertion } catch is CatalogSpeechQuality.Failure { }
        guard let oversizedID = UUID(uuidString: oversized.deletingLastPathComponent().lastPathComponent) else { throw Failure.assertion }
        try reloaded.remove(oversizedID)
        _ = try reloaded.destination(identity: identity)
        guard FileManager.default.fileExists(atPath: passed.path), FileManager.default.fileExists(atPath: rejected.path) else { throw Failure.assertion }
        let report: [String: Any] = ["acceptedPositive":true,"rejectedExtraWord":true,"longRetainedUnverified":true,"canceledRetained":true,"missingASRRetained":true,"historyReload":true,"incompleteHistoryRecovery":true,"storageCapRecovery":true,"priorGoodPreserved":true,"positiveCheckSeconds":pass.checkSeconds,"negativeCheckSeconds":fail.checkSeconds,"physicalDeviceVerified":false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: base.appendingPathComponent("quality-lifecycle-results.json"))
    }
}
