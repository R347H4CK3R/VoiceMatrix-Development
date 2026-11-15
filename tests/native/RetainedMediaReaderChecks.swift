import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main struct Checks {
    static func reject(_ body: () throws -> Void) throws {
        do { try body() } catch { return }
        fatalError("Unsafe or changed source was accepted")
    }
    static func rejectChanged(_ body: () throws -> Void) throws {
        do { try body() } catch RetainedMediaReader.Failure.changed { return }
        fatalError("Changed source was accepted")
    }
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.wav")
        let payload = Data((0..<2_200_000).map { UInt8($0 % 251) })
        try payload.write(to: file)
        var received = Data(), chunks = 0
        let count = try RetainedMediaReader.read(file, maximumBytes: Int64(payload.count)) {
            precondition($0.count <= 1_048_576); chunks += 1; received.append($0)
        }
        precondition(received == payload && count == payload.count && chunks == 3)
        var consumed = false
        try reject { try RetainedMediaReader.read(file, maximumBytes: 10) { _ in consumed = true } }
        precondition(!consumed)
        try reject { try RetainedMediaReader.read(root, maximumBytes: 100) { _ in } }
        try reject { try RetainedMediaReader.read(root.appendingPathComponent("missing"), maximumBytes: 100) { _ in } }
        try reject { try RetainedMediaReader.read(URL(string: "https://example.invalid/source.wav")!, maximumBytes: 100) { _ in } }
        let empty = root.appendingPathComponent("empty.wav")
        try Data().write(to: empty)
        try reject { try RetainedMediaReader.read(empty, maximumBytes: 100) { _ in } }
        let link = root.appendingPathComponent("link.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try reject { try RetainedMediaReader.read(link, maximumBytes: 3_000_000) { _ in } }
        let fifo = root.appendingPathComponent("pipe.wav")
        precondition(mkfifo(fifo.path, mode_t(0o600)) == 0)
        try reject { try RetainedMediaReader.read(fifo, maximumBytes: 100) { _ in } }
        // Mutations are deliberate test fixtures. Production reader never changes data.
        let growing = root.appendingPathComponent("growing.wav")
        try payload.write(to: growing)
        var grew = false
        try reject {
            try RetainedMediaReader.read(growing, maximumBytes: 3_000_000) { _ in
                if !grew {
                    grew = true
                    let output = try FileHandle(forWritingTo: growing)
                    defer { try? output.close() }
                    try output.seekToEnd(); try output.write(contentsOf: Data([42]))
                }
            }
        }
        let shrinking = root.appendingPathComponent("shrinking.wav")
        try payload.write(to: shrinking)
        var shrank = false
        try reject {
            try RetainedMediaReader.read(shrinking, maximumBytes: 3_000_000) { _ in
                if !shrank {
                    shrank = true
                    let output = try FileHandle(forWritingTo: shrinking)
                    defer { try? output.close() }
                    try output.truncate(atOffset: 1)
                }
            }
        }
        let rewritten = root.appendingPathComponent("rewritten.wav")
        try payload.write(to: rewritten)
        var rewrote = false
        try rejectChanged {
            try RetainedMediaReader.read(rewritten, maximumBytes: 3_000_000) { _ in
                if !rewrote {
                    rewrote = true
                    let output = try FileHandle(forWritingTo: rewritten)
                    defer { try? output.close() }
                    // Change already-consumed bytes, keeping the total size identical.
                    try output.write(contentsOf: Data([42]))
                    try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: rewritten.path)
                }
            }
        }
        let rewrittenBytes = try Data(contentsOf: rewritten)
        precondition(rewrittenBytes.count == payload.count)
        let replaced = root.appendingPathComponent("replaced.wav")
        try payload.write(to: replaced)
        let replacement = Data(repeating: 7, count: payload.count)
        var swapped = false
        try rejectChanged {
            try RetainedMediaReader.read(replaced, maximumBytes: 3_000_000) { _ in
                if !swapped {
                    swapped = true
                    // Atomic replacement keeps the old descriptor readable, but the
                    // next pipeline stage would reopen this new same-size file.
                    try replacement.write(to: replaced, options: .atomic)
                }
            }
        }
        let replacedBytes = try Data(contentsOf: replaced)
        precondition(replacedBytes == replacement)
        let restoredTime = root.appendingPathComponent("restored-time.wav")
        try payload.write(to: restoredTime)
        var originalStat = stat()
        precondition(lstat(restoredTime.path, &originalStat) == 0)
#if canImport(Darwin)
        var originalTimes = [originalStat.st_atimespec, originalStat.st_mtimespec]
#else
        var originalTimes = [originalStat.st_atim, originalStat.st_mtim]
#endif
        var restored = false
        try rejectChanged {
            try RetainedMediaReader.read(restoredTime, maximumBytes: 3_000_000) { _ in
                if !restored {
                    restored = true
                    // Ensure the deliberate edit is observably later even on a fast host.
                    usleep(10_000)
                    let output = try FileHandle(forWritingTo: restoredTime)
                    defer { try? output.close() }
                    try output.write(contentsOf: Data([42]))
                    precondition(utimensat(AT_FDCWD, restoredTime.path, &originalTimes, 0) == 0)
                    var edited = stat()
                    precondition(lstat(restoredTime.path, &edited) == 0)
#if canImport(Darwin)
                    precondition(edited.st_mtimespec.tv_sec == originalStat.st_mtimespec.tv_sec && edited.st_mtimespec.tv_nsec == originalStat.st_mtimespec.tv_nsec)
#else
                    precondition(edited.st_mtim.tv_sec == originalStat.st_mtim.tv_sec && edited.st_mtim.tv_nsec == originalStat.st_mtim.tv_nsec)
#endif
                    precondition(edited.st_size == originalStat.st_size)
                }
            }
        }
        let swappedLink = root.appendingPathComponent("swapped-link.wav")
        let parked = root.appendingPathComponent("parked-original.wav")
        try payload.write(to: swappedLink)
        var linked = false
        try rejectChanged {
            try RetainedMediaReader.read(swappedLink, maximumBytes: 3_000_000) { _ in
                if !linked {
                    linked = true
                    try FileManager.default.moveItem(at: swappedLink, to: parked)
                    try FileManager.default.createSymbolicLink(at: swappedLink, withDestinationURL: replaced)
                }
            }
        }
        let parkedBytes = try Data(contentsOf: parked)
        let targetBytes = try Data(contentsOf: replaced)
        precondition(parkedBytes == payload && targetBytes == replacement)
        let linkedDestination = try FileManager.default.destinationOfSymbolicLink(atPath: swappedLink.path)
        precondition(linkedDestination == replaced.path)
        let canceled = Task.detached {
            try RetainedMediaReader.read(file, maximumBytes: 3_000_000) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        do { _ = try await canceled.value; fatalError("Cancellation ignored") }
        catch is CancellationError { }
        // The actual retained source and link survive every rejected/cancelled operation.
        let preserved = try Data(contentsOf: file)
        precondition(preserved == payload)
        precondition(FileManager.default.fileExists(atPath: link.path))
        print("Retained media checks passed: exact bytes, bounds, types, growth, truncation, cancellation and preservation")
    }
}
