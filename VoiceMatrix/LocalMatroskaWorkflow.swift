#if os(iOS)
import Foundation
import CoreFoundation
import CryptoKit
import Darwin

@MainActor
enum LocalMatroskaWorkflow {
    typealias Media = LocalMediaAcquisition.Result
    typealias Progress = @Sendable (String) -> Void
    typealias Decision = @MainActor (String) async throws -> String
    typealias Remux = @MainActor (URL, URL, Int64) async throws -> Void
    typealias Derive = @MainActor (URL, String, URL, Int64) async throws -> LocalMatroskaDerivedMedia.Receipt

    struct Output {
        let acquisition: Media
        let mkv: Media
        let derived: Media
        let timing: LocalMatroskaDerivedMedia.Receipt
    }

    enum Failure: Error, Equatable { case unsafe, changed, busy, budget, policy, timeout }

    private struct Journal: Codable {
        let schemaVersion: Int
        let jobID: UUID
        let attemptID: UUID
        let acquisition: Media
        var mkv: Media?
        var derived: Media?
        var timing: LocalMatroskaDerivedMedia.Receipt?
        var complete: Bool
    }

    private static var leases = Set<String>()
    private static let maxFile: Int64 = 536_870_912
    private static let maxJournal: Int64 = 16_384
    private static let diskReserve: Int64 = 800_000_000

    static func run(jobDirectory: URL, jobID: UUID, attemptID: UUID, acquisition: Media,
                    maximumRetainedBytes: Int64, progress: @escaping Progress = { _ in }) async throws -> Output {
        try await run(jobDirectory: jobDirectory, jobID: jobID, attemptID: attemptID, acquisition: acquisition,
                      maximumRetainedBytes: maximumRetainedBytes, progress: progress, decide: nativeDecision,
                      remux: { input, output, limit in
                          _ = try await LocalMKVExport.export(input: input, destination: output, maxBytes: limit)
                      }, derive: { input, sha, output, limit in
                          try await LocalMatroskaDerivedMedia.derive(sourceMKV: input, expectedSHA256: sha,
                                                                   destination: output, maximumBytes: limit)
                      })
    }

    static func run(jobDirectory: URL, jobID: UUID, attemptID: UUID, acquisition: Media,
                    maximumRetainedBytes: Int64, progress: @escaping Progress = { _ in },
                    decide: Decision, remux: Remux, derive: Derive,
                    volumeCapacity: (URL) throws -> Int64 = availableCapacity) async throws -> Output {
        guard jobDirectory.isFileURL, maximumRetainedBytes > 0 else { throw Failure.unsafe }
        try valid(acquisition, suffix: "mp4")
        let directory = jobDirectory.standardizedFileURL
        let lease = try identity(directory)
        guard leases.insert(lease).inserted else { throw Failure.busy }
        defer { leases.remove(lease) }

        func check() throws {
            try Task.checkCancellation()
            guard try identity(directory) == lease else { throw Failure.changed }
        }
        func remaining() throws -> Int64 {
            try check()
            return max(0, maximumRetainedBytes - (try LocalMediaAcquisition.retainedBytes(root: directory)))
        }

        let journalURL = directory.appendingPathComponent("strict-matroska-v1.json")
        func loadJournal() throws -> Data? {
            guard try exists(journalURL) else { return nil }
            var data = Data()
            try RetainedMediaReader.read(journalURL, maximumBytes: maxJournal) { data.append($0) }
            return data
        }
        try check()
        var journalSnapshot = try loadJournal()
        func save(_ journal: Journal) throws {
            let data = try JSONEncoder().encode(journal)
            guard try remaining() >= Int64(data.count), try loadJournal() == journalSnapshot else {
                throw Failure.changed
            }
            try check()
            if journalSnapshot == nil {
                let staging = directory.appendingPathComponent(".strict-journal-" + UUID().uuidString)
                try data.write(to: staging, options: .withoutOverwriting)
                defer { if (try? identity(directory)) == lease { try? FileManager.default.removeItem(at: staging) } }
                try check()
                try FileManager.default.linkItem(at: staging, to: journalURL)
            } else {
                try data.write(to: journalURL, options: .atomic)
            }
            journalSnapshot = data
        }

        var state = Journal(schemaVersion: 1, jobID: jobID, attemptID: attemptID,
                            acquisition: acquisition, complete: false)
        if let data = journalSnapshot {
            try validateJournalKeys(data)
            state = try JSONDecoder().decode(Journal.self, from: data)
            guard state.schemaVersion == 1, state.jobID == jobID, state.attemptID == attemptID,
                  state.acquisition.file == acquisition.file, state.acquisition.sha256 == acquisition.sha256,
                  state.acquisition.bytes == acquisition.bytes, (state.derived == nil) == (state.timing == nil),
                  state.derived == nil || state.mkv != nil, !state.complete || state.derived != nil else {
                throw Failure.changed
            }
        }
        let original = directory.appendingPathComponent(acquisition.file)
        if try state.mkv == nil || exists(original) {
            try await LocalMediaAcquisition.verify(acquisition, folder: directory)
        }
        try check()

        if state.mkv == nil {
            try await admit("acquisition", action: "prepare", state: state, decide: decide)
            let room = try remaining()
            guard room > acquisition.bytes + maxJournal else { throw Failure.budget }
            let limit = min(maxFile, room - acquisition.bytes - maxJournal)
            guard try volumeCapacity(directory) >= acquisition.bytes + limit + diskReserve else { throw Failure.budget }
            let staging = directory.appendingPathComponent(".strict-original-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
            defer { if (try? identity(directory)) == lease { try? FileManager.default.removeItem(at: staging) } }
            let snapshot = staging.appendingPathComponent("source.mp4")
            try await stageOriginal(original, expected: acquisition, destination: snapshot)
            try check()
            let destination = directory.appendingPathComponent("strict-" + UUID().uuidString.lowercased() + ".mkv")
            progress("Preparing Matroska from the verified original.")
            try check()
            try await remux(snapshot, destination, limit)
            try check()
            try await LocalMediaAcquisition.verify(acquisition, folder: directory)
            let mkv = try await digest(destination, limit: limit)
            guard mkv.sha256 != acquisition.sha256 else { throw Failure.changed }
            state.mkv = mkv
            try save(state)
        }
        guard let mkv = state.mkv else { throw Failure.changed }
        try valid(mkv, suffix: "mkv", owned: true)
        guard mkv.sha256 != acquisition.sha256 else { throw Failure.changed }
        try await LocalMediaAcquisition.verify(mkv, folder: directory)
        try check()

        if state.derived == nil {
            try await admit("mkvVerified", action: "derive", state: state, decide: decide)
            let limit = min(maxFile, (try remaining() - maxJournal) / 2)
            guard limit >= mkv.bytes, try volumeCapacity(directory) >= 2 * limit + diskReserve else { throw Failure.budget }
            let destination = directory.appendingPathComponent("strict-" + UUID().uuidString.lowercased() + ".mov")
            progress("Decoding analysis media from the verified MKV.")
            try check()
            let timing = try await derive(directory.appendingPathComponent(mkv.file), mkv.sha256, destination, limit)
            try check()
            let mov = try await digest(destination, limit: limit)
            try validate(timing, mkv: mkv, mov: mov, original: acquisition)
            try await LocalMediaAcquisition.verify(mkv, folder: directory)
            state.derived = mov
            state.timing = timing
            try save(state)
        }
        guard let mov = state.derived, let timing = state.timing else { throw Failure.changed }
        try valid(mov, suffix: "mov", owned: true)
        try validate(timing, mkv: mkv, mov: mov, original: acquisition)
        if !state.complete { try await admit("derivedVerified", action: "complete", state: state, decide: decide) }
        try await LocalMediaAcquisition.verify(mkv, folder: directory)
        try await LocalMediaAcquisition.verify(mov, folder: directory)
        try check()
        guard try loadJournal() == journalSnapshot else { throw Failure.changed }
        if !state.complete { state.complete = true; try save(state) }
        return Output(acquisition: acquisition, mkv: mkv, derived: mov, timing: timing)
    }

    static func availableCapacity(_ directory: URL) throws -> Int64 {
        guard let capacity = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { throw Failure.budget }
        return capacity
    }

    private static func stageOriginal(_ url: URL, expected: Media, destination: URL) async throws {
        let size = expected.bytes, sha = expected.sha256
        let worker = Task.detached {
            let fd = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o400))
            guard fd >= 0 else { throw Failure.unsafe }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            defer { try? handle.close() }
            var hash = SHA256()
            let count = try RetainedMediaReader.read(url, maximumBytes: size) {
                hash.update(data: $0)
                try handle.write(contentsOf: $0)
            }
            guard count == size, hash.finalize().map({ String(format: "%02x", $0) }).joined() == sha else {
                throw Failure.changed
            }
            try handle.synchronize()
        }
        try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func valid(_ media: Media, suffix: String, owned: Bool = false) throws {
        let stem = owned ? "strict-[a-f0-9-]{36}" : "[A-Za-z0-9_-]{1,128}"
        guard media.file.range(of: "^" + stem + "[.]" + suffix + "$", options: .regularExpression) != nil,
              media.file.hasSuffix("." + suffix), media.sha256.utf8.count == 64,
              media.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              (1...maxFile).contains(media.bytes) else { throw Failure.unsafe }
    }

    private static func validate(_ r: LocalMatroskaDerivedMedia.Receipt, mkv: Media, mov: Media, original: Media) throws {
        guard r.mkvSHA256 == mkv.sha256, r.movSHA256 == mov.sha256, r.movBytes == mov.bytes,
              mov.sha256 != mkv.sha256, mov.sha256 != original.sha256,
              (1...1_000_000).contains(r.audioPackets), (8_000...192_000).contains(r.audioSampleRate),
              (1...2).contains(r.audioChannels), r.audioFrames > 0, r.audioFrames <= Int64(r.audioSampleRate) * 1801,
              (1...1_000_000).contains(r.videoFrames), (1...1_800_100).contains(r.videoEndMilliseconds),
              (0..<1024).contains(r.discardFrames), r.audioFrames == r.audioPackets * 1024 - r.discardFrames else {
            throw Failure.changed
        }
    }

    private static func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw Failure.unsafe }
            return true
        }
        guard errno == ENOENT else { throw Failure.unsafe }
        return false
    }

    private static func identity(_ url: URL) throws -> String {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.unsafe }
        return "\(info.st_dev):\(info.st_ino)"
    }

    private static func digest(_ url: URL, limit: Int64) async throws -> Media {
        let worker = Task.detached {
            var hash = SHA256()
            let bytes = try RetainedMediaReader.read(url, maximumBytes: limit) { hash.update(data: $0) }
            return Media(file: url.lastPathComponent, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(), bytes: bytes)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    private static func strictJSONObject(_ data: Data) throws -> [String: Any] {
        guard let text = String(data: data, encoding: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Failure.policy }
        // Scan complete quoted tokens; only colons outside strings are structural keys.
        let tokens = try NSRegularExpression(pattern: #""(?:[^"\\]|\\.)*"|[:]"#)
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
        let keys = tokens.filter { token in
            Range(token.range, in: text).map { text[$0] == ":" } ?? false
        }.count
        func decodedKeys(_ value: Any) -> Int {
            if let dictionary = value as? [String: Any] {
                return dictionary.count + dictionary.values.reduce(0) { $0 + decodedKeys($1) }
            }
            if let array = value as? [Any] { return array.reduce(0) { $0 + decodedKeys($1) } }
            return 0
        }
        guard keys == decodedKeys(root) else { throw Failure.policy }
        return root
    }

    private static func validateJournalKeys(_ data: Data) throws {
        guard let root = try? strictJSONObject(data) else { throw Failure.changed }
        let required: Set<String> = ["schemaVersion", "jobID", "attemptID", "acquisition", "complete"]
        let keys = Set(root.keys)
        guard required.isSubset(of: keys), keys.isSubset(of: required.union(["mkv", "derived", "timing"])) else {
            throw Failure.changed
        }
        for name in ["acquisition", "mkv", "derived"] where root[name] != nil {
            guard let media = root[name] as? [String: Any], Set(media.keys) == ["file", "sha256", "bytes"] else {
                throw Failure.changed
            }
        }
        if let timing = root["timing"] {
            guard let fields = timing as? [String: Any],
                  Set(fields.keys) == ["mkvSHA256", "movSHA256", "movBytes", "audioPackets", "audioFrames", "audioSampleRate",
                                       "audioChannels", "videoFrames", "videoEndMilliseconds", "discardFrames"] else {
                throw Failure.changed
            }
        }
    }

    private static func admit(_ stage: String, action: String, state: Journal, decide: Decision) async throws {
        try Task.checkCancellation()
        let job = state.jobID.uuidString.lowercased(), attempt = state.attemptID.uuidString.lowercased()
        let mkv: Any = state.mkv.map {
            ["jobID": job, "attemptID": attempt, "acquisitionSHA256": state.acquisition.sha256, "mkvSHA256": $0.sha256] as Any
        } ?? NSNull()
        let derived: Any = state.derived.map {
            ["jobID": job, "attemptID": attempt, "mkvSHA256": state.mkv?.sha256 ?? "", "movSHA256": $0.sha256] as Any
        } ?? NSNull()
        let request: [String: Any] = ["schemaVersion": 1, "jobID": job, "attemptID": attempt, "stage": stage,
                                      "acquisitionSHA256": state.acquisition.sha256, "mkv": mkv, "derived": derived]
        let result = try await decide(String(decoding: JSONSerialization.data(withJSONObject: request), as: UTF8.self))
        try Task.checkCancellation()
        guard result.utf8.count <= 4096, var reply = try? strictJSONObject(Data(result.utf8)),
              let version = reply.removeValue(forKey: "schemaVersion") as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              !["d", "f"].contains(String(cString: version.objCType)), version.intValue == 1,
              (reply as? [String: String]) == ["jobID": job, "attemptID": attempt, "stage": stage, "action": action] else {
            throw Failure.policy
        }
    }

    private static func nativeDecision(_ request: String) async throws -> String {
        try Task.checkCancellation()
        let provider = VMWebKitChallengeProvider()
        let runtime = VMPythonRuntime(javaScriptEvaluator: { script, input, identity, completion in
            provider.evaluateScript(script, inputJSON: input, requestID: identity) { result, error in completion(result, error) }
        }, canceller: { identity in provider.cancelRequest(identity) })
        let pending = Pending(runtime)
        return try await withTaskCancellationHandler {
            let timer = Task { @MainActor in
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                pending.abort(Failure.timeout)
            }
            defer { timer.cancel() }
            return try await withCheckedThrowingContinuation { pending.start(request, continuation: $0) }
        } onCancel: {
            Task { @MainActor in pending.abort(CancellationError()) }
        }
    }

    @MainActor
    private final class Pending {
        private let runtime: VMPythonRuntime
        private var identity: String?
        private var continuation: CheckedContinuation<String, Error>?
        private var terminated: Error?
        init(_ runtime: VMPythonRuntime) { self.runtime = runtime }
        func start(_ request: String, continuation: CheckedContinuation<String, Error>) {
            if let terminated { continuation.resume(throwing: terminated); return }
            self.continuation = continuation
            identity = runtime.decideMKVStageJSON(request) { result, _ in
                guard let pending = self.continuation else { return }
                self.continuation = nil
                self.identity = nil
                if let result { pending.resume(returning: result) }
                else { pending.resume(throwing: Failure.policy) }
            }
        }
        func abort(_ error: Error) {
            terminated = error
            if let identity { runtime.cancelRequest(identity); self.identity = nil }
            if let continuation { self.continuation = nil; continuation.resume(throwing: error) }
        }
    }
}
#endif
