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
