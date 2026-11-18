import Foundation
import CryptoKit
import Darwin

/// Bounded private review metadata. No writes to retained media, clip receipts, or voice stores.
struct ClipSpeakerReviewStore: Sendable {
    typealias Clip = SeparationClipHandoff.Input
    typealias Analysis = LocalSpeakerDiarization.Analysis

    enum Failure: LocalizedError, Equatable {
        case unsupported, unsafe, bounds, alias, alreadySaved
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Speaker review needs a retained clip from 3 to 10 seconds."
            case .unsafe: return "The clip or its saved review could not be verified. Existing files were kept."
            case .bounds: return "This review exceeds the local storage or evidence limit. Existing files were kept."
            case .alias: return "Use a label of 1 to 80 characters without line breaks or control characters."
            case .alreadySaved: return "A review already exists for this clip. Reopen it to edit labels."
            }
        }
    }

    struct Binding: Codable, Equatable, Sendable {
        let clipID: UUID
        let clipSHA256: String
        let receiptSHA256: String
        let analysisSHA256: String
    }

    struct Alias: Codable, Equatable, Sendable {
        let binding: Binding
        let speaker: String
        let name: String
    }

    struct Group: Identifiable {
        let id: String
        let speaker: String
        let turns: [LocalSpeakerPolicy.Segment]
        let hasPolicyWindow: Bool
    }

    struct Review: Codable, Sendable {
        let version: Int
        let binding: Binding
        let analysis: Analysis
        var aliases: [Alias]

        func alias(for speaker: String) -> String? { aliases.first { $0.speaker == speaker }?.name }

        // IDs are names for anonymous guesses, scoped to this exact analysis.
        var groups: [Group] {
            guard analysis.rawOverlap?.counts.contains(where: { $0 > 0 }) == true else { return [] }
            let turns = Dictionary(grouping: analysis.segments, by: \.speaker).mapValues {
                $0.sorted { ($0.start, $0.end) < ($1.start, $1.end) }
            }
            let order = turns.keys.sorted { (turns[$0]![0].start, $0) < (turns[$1]![0].start, $1) }
            let windows = Set(analysis.speakerWindows.filter { !$0.windows.isEmpty }.map(\.speaker))
            return order.enumerated().map { index, speaker in
                Group(id: "S\(index + 1)", speaker: speaker, turns: turns[speaker]!,
                      hasPolicyWindow: windows.contains(speaker))
            }
        }

        var hasOverlap: Bool {
            if analysis.rawOverlap?.counts.contains(where: { $0 >= 2 }) == true { return true }
            var ends: [String: Double] = [:]
            for turn in analysis.segments.sorted(by: { $0.start < $1.start }) {
                if ends.contains(where: { $0.key != turn.speaker && $0.value > turn.start }) { return true }
                ends[turn.speaker] = max(ends[turn.speaker] ?? 0, turn.end)
            }
            return false
        }
    }

    private static let version = 1
    private static let maximumBytes: Int64 = 256 * 1024
    private static let maximumEntries = 128
    private let clipRoot: URL
    private var clipStore: SeparationStore { SeparationStore(root: clipRoot) }
    let root: URL

    init(clipStore: SeparationStore = .standard) {
        self.clipRoot = clipStore.root
        // Not inside immutable Clip-* directories; it doesn't consume clip admission slots.
        root = clipStore.root.deletingLastPathComponent()
            .appendingPathComponent(clipStore.root.lastPathComponent + "-SpeakerReviews", isDirectory: true)
    }

    static func supports(_ clip: Clip) -> Bool { (132_300...441_000).contains(clip.frames) }

    /// This verifies the canonical handoff receipt and the WAV, never a caller-supplied lookalike.
    func verify(_ clip: Clip) throws {
        guard Self.supports(clip) else { throw Failure.unsupported }
        guard clip.url.isFileURL, clip.url.standardizedFileURL.path == ownedWave(clip.id).standardizedFileURL.path else {
            throw Failure.unsafe
        }
        try SeparationClipHandoff.validate(clip, store: clipStore)
    }

    /// Discover only clips prepared from the selected source; no inference or writes.
    /// Full receipt and WAV validation occurs when a clip is opened.
    func preparedClips(for source: SeparationClipHandoff.Source) throws -> [Clip] {
        guard try directoryExists(clipStore.root) else { return [] }
        let contents = try FileManager.default.contentsOfDirectory(at: clipStore.root, includingPropertiesForKeys: nil)
        guard contents.count <= 64 else { throw Failure.bounds }
        var clips: [Clip] = []
        for directory in contents where directory.lastPathComponent.hasPrefix("Clip-") {
            try Task.checkCancellation()
            do {
                guard try directoryExists(directory) else { continue }
                let data = try read(directory.appendingPathComponent("receipt.json"), maximumBytes: 4096)
                let receipt = try JSONDecoder().decode(SeparationClipHandoff.Receipt.self, from: data)
                guard directory.lastPathComponent == "Clip-" + receipt.id.uuidString,
                      receipt.sourceJobID == source.jobID, receipt.sourceSHA256 == source.sha256,
                      receipt.clipSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      receipt.actualStart.isFinite, receipt.actualStart >= 0,
                      receipt.actualStart + Double(receipt.frames) / 44_100 <= 1800 else { continue }
                let clip = Clip(id: receipt.id, url: ownedWave(receipt.id), sha256: receipt.clipSHA256,
                                receiptSHA256: Self.digest(data), start: receipt.actualStart, frames: receipt.frames)
                if Self.supports(clip) { clips.append(clip) }
            } catch is CancellationError {
                throw CancellationError()
            } catch { continue } // Unreadable originals are not deleted or used.
        }
        return clips.sorted { ($0.start, $0.frames, $0.id.uuidString) < ($1.start, $1.frames, $1.id.uuidString) }
    }

    // Decode a verified, private snapshot. This prevents a transient pathname change
    // from causing the diarizer to read different audio between two successful hashes.
    func snapshot(for clip: Clip) throws -> URL {
        try verify(clip)
        try admit()
        let snapshots = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard snapshots.filter({ $0.lastPathComponent.hasPrefix(".inference-") }).count < 4 else { throw Failure.bounds }
        let data = try read(ownedWave(clip.id), maximumBytes: Int64(44 + clip.frames * 8))
        guard data.count == 44 + clip.frames * 8, Self.digest(data) == clip.sha256 else { throw Failure.unsafe }
        try Task.checkCancellation()
        return try stage(data, name: ".inference-" + UUID().uuidString + ".wav")
    }

    func validate(_ analysis: Analysis, for clip: Clip) throws {
        guard Self.supports(clip), analysis.selectionPolicyVersion == 5,
              analysis.rawOverlap?.sourceSHA256 == clip.sha256,
              analysis.seconds.isFinite,
              // Allow one 16 kHz sample of conversion rounding, not a different interval.
              abs(analysis.seconds - Double(clip.frames) / 44_100) <= 1.0 / 16_000 + 1e-9,
              analysis.segments.count <= 1024 else { throw Failure.unsafe }
        _ = try LocalSpeakerDiarization.validatedForCurrentPolicy(analysis)
    }

    func load(for clip: Clip) throws -> Review? {
        try verify(clip)
        return try checkedReview(for: clip)
    }

    @discardableResult
    func publish(_ analysis: Analysis, for clip: Clip) throws -> Review {
        try verify(clip)
        try validate(analysis, for: clip)
        guard try checkedReview(for: clip) == nil else { throw Failure.alreadySaved }
        let review = Review(version: Self.version, binding: try binding(for: clip, analysis: analysis),
                            analysis: analysis, aliases: [])
        try write(review, to: sidecar(clip), replacing: false)
        return review
    }

    func saveAlias(_ name: String?, speaker: String, expected: Review, for clip: Clip) throws -> Review {
        guard var current = try load(for: clip), current.binding == expected.binding,
              current.aliases == expected.aliases,
              current.groups.contains(where: { $0.speaker == speaker }) else { throw Failure.unsafe }
        let normalized = try name.map(Self.checkedAlias)
        current.aliases.removeAll { $0.speaker == speaker }
        if let normalized { current.aliases.append(Alias(binding: current.binding, speaker: speaker, name: normalized)) }
        current.aliases.sort { $0.speaker < $1.speaker }
        try write(current, to: sidecar(clip), replacing: true)
        return current
    }

    static func checkedAlias(_ name: String) throws -> String {
        let forbidden = CharacterSet.controlCharacters.union(.newlines)
        guard name.utf8.count <= 2048, !name.unicodeScalars.contains(where: { forbidden.contains($0) }) else { throw Failure.alias }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard (1...80).contains(trimmed.count) else { throw Failure.alias }
        return trimmed
    }

    private func checkedReview(for clip: Clip) throws -> Review? {
        guard try directoryExists(root) else { return nil }
        let target = sidecar(clip)
        var info = stat()
        if lstat(target.path, &info) != 0 {
            guard errno == ENOENT else { throw Failure.unsafe }
            return nil
        }
        let review = try JSONDecoder().decode(Review.self, from: read(target, maximumBytes: Self.maximumBytes))
        try validate(review.analysis, for: clip)
        guard review.version == Self.version, review.binding == (try binding(for: clip, analysis: review.analysis)),
              review.aliases.count <= 32, Set(review.aliases.map(\.speaker)).count == review.aliases.count else { throw Failure.unsafe }
        let speakers = Set(review.groups.map(\.speaker))
        for alias in review.aliases {
            guard alias.binding == review.binding, speakers.contains(alias.speaker),
                  try Self.checkedAlias(alias.name) == alias.name else { throw Failure.unsafe }
        }
        return review
    }

    private func binding(for clip: Clip, analysis: Analysis) throws -> Binding {
        Binding(clipID: clip.id, clipSHA256: clip.sha256, receiptSHA256: clip.receiptSHA256,
                analysisSHA256: Self.digest(try Self.encode(analysis)))
    }

    private func ownedWave(_ id: UUID) -> URL {
        clipStore.root.appendingPathComponent("Clip-" + id.uuidString, isDirectory: true).appendingPathComponent("clip.wav")
    }

    private func sidecar(_ clip: Clip) -> URL { root.appendingPathComponent(clip.id.uuidString + ".json") }

    private func directoryExists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return false }
            throw Failure.unsafe
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.unsafe }
        return true
    }

    private func admit() throws {
        if try !directoryExists(root) {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        }
        guard try directoryExists(root),
              try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count < Self.maximumEntries else {
            throw Failure.bounds
        }
    }

    private func read(_ url: URL, maximumBytes: Int64) throws -> Data {
        var data = Data()
        try RetainedMediaReader.read(url, maximumBytes: maximumBytes) { data.append($0) }
        return data
    }

    private func write(_ review: Review, to target: URL, replacing: Bool) throws {
        let data = try Self.encode(review)
        guard data.count <= Self.maximumBytes else { throw Failure.bounds }
        try Task.checkCancellation()
        try admit()
        let staged = try stage(data, name: ".review-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staged) }
        try Task.checkCancellation()
        let result = replacing ? rename(staged.path, target.path) : renamex_np(staged.path, target.path, UInt32(RENAME_EXCL))
        guard result == 0 else { throw Failure.unsafe }
    }

    private func stage(_ data: Data, name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw Failure.unsafe }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            return url
        } catch {
            try? handle.close()
            // This attempt exclusively created the incomplete scratch file.
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
