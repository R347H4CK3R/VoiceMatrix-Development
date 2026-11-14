import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Bounded reads of a single regular file. The app-container ancestors are trusted.
/// No media is changed or removed, including when a read is cancelled or rejected.
enum RetainedMediaReader {
    enum Failure: Error { case unsafe, bounds, changed }

    @discardableResult
    static func read(_ url: URL, maximumBytes: Int64, cancellable: Bool = true,
                     consume: (Data) throws -> Void) throws -> Int64 {
        if cancellable { try Task.checkCancellation() }
        guard url.isFileURL, maximumBytes > 0 else { throw Failure.unsafe }
        // Open nonblocking before checking type: a FIFO must never stall recovery.
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.unsafe }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var before = stat()
        guard fstat(fd, &before) == 0,
              before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else { throw Failure.unsafe }
        let expected = Int64(before.st_size)
        guard expected > 0, expected <= maximumBytes else { throw Failure.bounds }
        var count: Int64 = 0
        while true {
            if cancellable { try Task.checkCancellation() }
            guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { break }
            // Reject growth before exposing excess bytes to the caller.
            guard Int64(bytes.count) <= expected - count else { throw Failure.changed }
            try consume(bytes)
            count += Int64(bytes.count)
        }
        if cancellable { try Task.checkCancellation() }
        var after = stat()
        guard count == expected, fstat(fd, &after) == 0,
              Int64(after.st_size) == expected else { throw Failure.changed }
        return count
    }
}
