import Foundation
import CryptoKit

/// Rendered output is retained independently of whether local ASR can verify it.
@MainActor final class CatalogSpeechQuality {
    struct Result: Codable, Sendable {
        let verified: Bool
        let reason: String
        let requestedText: String
        let recognizedText: String?
        let audioSHA256: String
        let wordErrorRate: Double?
        let checkSeconds: Double
        let likenessVerified = false
    }
    struct Identity: Codable, Sendable {
        let voiceID: String
        let referenceHash: String
        let requestedText: String
        let controls: String
        let created: Date
    }
    struct HistoryItem: Identifiable {
        let id: UUID
        let audio: URL?
        let identity: Identity
        let reason: String
        let verified: Bool
    }
    struct Pending {
        let audio: URL
        let voiceID: String
        let referenceHash: String
        let reason: String
    }
    enum Failure: LocalizedError {
        case storage
        var errorDescription: String? { "Speech-check history is full or storage is unavailable. Export retained audio and free space before creating more speech; nothing was deleted." }
    }
    private let root: URL
    private let asrBundle: URL?
    init(root: URL, asrBundle: URL?) { self.root = root; self.asrBundle = asrBundle }
    func destination(identity: Identity) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .volumeAvailableCapacityKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              (values.volumeAvailableCapacity ?? 0) >= 200 * 1024 * 1024 else { throw Failure.storage }
        guard let scan = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) else { throw Failure.storage }
        var bytes = 0, count = 0
        for case let file as URL in scan {
            count += 1
            let item = try file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard count <= 10000, item.isSymbolicLink != true else { throw Failure.storage }
            bytes += item.fileSize ?? 0
            guard bytes <= 256 * 1024 * 1024 else { throw Failure.storage }
        }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try JSONEncoder().encode(identity).write(to: folder.appendingPathComponent("request.json"), options: .atomic)
        return folder.appendingPathComponent("speech.wav")
    }
    func history(limit: Int = 50) throws -> [HistoryItem] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let rootInfo = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true else { throw Failure.storage }
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])
        guard folders.count <= 10000 else { throw Failure.storage }
        var items: [HistoryItem] = []
        let newest = folders.sorted {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }.prefix(max(1, min(limit, 10000)))
        for folder in newest {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw Failure.storage }
            let rendered = folder.appendingPathComponent("speech.wav")
            let raw = folder.appendingPathComponent("speech.raw.wav")
            let hasRendered = FileManager.default.fileExists(atPath: rendered.path)
            let audio: URL? = hasRendered ? rendered : (FileManager.default.fileExists(atPath: raw.path) ? raw : nil)
            if let audio {
                let audioInfo = try audio.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard audioInfo.isRegularFile == true, audioInfo.isSymbolicLink != true else { throw Failure.storage }
            }
            let identity = (try? JSONDecoder().decode(Identity.self, from: smallFile(folder.appendingPathComponent("request.json")))) ??
                Identity(voiceID: "Unknown (metadata unreadable)", referenceHash: "unknown", requestedText: "Request metadata unavailable. Retained audio can still be exported or deleted.", controls: "Unknown controls", created: .distantPast)
            let result = try? JSONDecoder().decode(Result.self, from: smallFile(folder.appendingPathComponent("word-check.json")))
            // Never restore a ready result from metadata alone. History playback/export is explicit review.
            let reason = !hasRendered ? (audio == nil ? "Interrupted before audio was produced. This attempt can be deleted." : "Incomplete raw audio retained after interruption. Not rendered or checked; export for recovery only.") : result.map { "Recorded check (not revalidated on reload): " + $0.reason } ?? "Interrupted or incomplete word check. Audio retained for manual review."
            items.append(HistoryItem(id: id, audio: audio, identity: identity, reason: reason, verified: false))
        }
        return Array(items.sorted { $0.identity.created > $1.identity.created }.prefix(max(1, min(limit, 10000))))
    }
    private func smallFile(_ file: URL) throws -> Data {
        let v = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true, let n = v.fileSize, n > 0, n <= 65536 else { throw Failure.storage }
        let data = try Data(contentsOf: file); guard data.count == n else { throw Failure.storage }; return data
    }
    func remove(_ id: UUID) throws {
        let rootInfo = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true else { throw Failure.storage }
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let info = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true else { throw Failure.storage }
        // Only called after explicit user confirmation, while no speech operation owns the directory.
        try FileManager.default.removeItem(at: folder)
    }
    func markUnverified(_ file: URL, expected: String, reason: String) throws {
        try save(Result(verified: false, reason: reason, requestedText: expected, recognizedText: nil,
            audioSHA256: try digest(file), wordErrorRate: nil, checkSeconds: 0), beside: file)
    }
    private func digest(_ file: URL) throws -> String {
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true,
              let size = info.fileSize, size > 0, size <= 192 * 1024 * 1024 else { throw Failure.storage }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256(), count = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            count += data.count; guard count <= size else { throw Failure.storage }; hash.update(data: data)
        }
        guard count == size else { throw Failure.storage }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    func check(_ file: URL, expected: String) async throws -> Result {
        let start = Date(), originalHash = try digest(file)
        let recognizer = OnDeviceTranscription(bundle: asrBundle)
        var result: Result
        do {
            let words = try await recognizer.transcribe(file)
            try Task.checkCancellation()
            let finalHash = try digest(file)
            let textHash = SHA256.hash(data: Data(words.utf8)).map { String(format: "%02x", $0) }.joined()
            let accepted = finalHash == originalHash && CatalogSpeechQualityPolicy.accepts(expected: expected, actual: words,
                audioHash: finalHash, evidenceAudioHash: recognizer.lastEvidence?.inputSHA256 ?? "",
                transcriptHash: textHash, evidenceTranscriptHash: recognizer.lastEvidence?.transcriptSHA256 ?? "")
            result = Result(verified: accepted,
                reason: accepted ? "Local word check passed. This is not a likeness or accuracy guarantee." : "Local recognition did not match the requested words. Recognition can be wrong; review the retained audio or try a different reference.",
                requestedText: expected, recognizedText: words, audioSHA256: originalHash,
                wordErrorRate: LocalStudioEvidence.wordErrorRate(expected: expected, actual: words), checkSeconds: Date().timeIntervalSince(start))
        } catch {
            result = Result(verified: false, reason: "Not automatically verified. " + error.localizedDescription + " Recognition can be wrong; the rendered audio was kept for review.",
                requestedText: expected, recognizedText: nil, audioSHA256: originalHash, wordErrorRate: nil, checkSeconds: Date().timeIntervalSince(start))
            try save(result, beside: file)
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            return result
        }
        try save(result, beside: file)
        try Task.checkCancellation()
        return result
    }
    private func save(_ result: Result, beside file: URL) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(result).write(to: file.deletingLastPathComponent().appendingPathComponent("word-check.json"), options: .atomic)
    }
}
