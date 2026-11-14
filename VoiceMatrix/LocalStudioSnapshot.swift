import Foundation

/// The small live snapshot is replaceable; the full append-only journal is not.
enum LocalStudioSnapshot {
    static let maximumBytes = 262_144
    // Older writers could emit 160 full events beyond the old 256 KiB read cap.
    // Permit bounded recovery without rewriting or deleting that original snapshot.
    static let maximumRecoveryBytes = 2_097_152
    enum Failure: LocalizedError {
        case tooLarge, unsafe
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "Job details exceed the recovery snapshot limit. Earlier saved state and the complete event journal were kept."
            case .unsafe: return "The retained job snapshot could not be read safely. Existing files were kept."
            }
        }
    }
    struct Encoded<Value> { let value: Value; let data: Data }
    static func encode<Value: Encodable>(_ value: Value, events: [LocalStudioJournal.Event],
                                        replacingEvents: (inout Value, [LocalStudioJournal.Event]) -> Void) throws -> Encoded<Value> {
        var copy = value
        var retained = Array(events.suffix(160))
        while true {
            replacingEvents(&copy, retained)
            let data = try JSONEncoder().encode(copy)
            if data.count <= maximumBytes { return Encoded(value: copy, data: data) }
            guard !retained.isEmpty else { throw Failure.tooLarge }
            // Geometric trimming bounds re-encoding work while keeping recent activity.
            // Every event has already been synchronized to the durable journal.
            retained.removeFirst(max(1, retained.count / 4))
        }
    }
    static func read(folder: URL) throws -> Data {
        guard folder.isFileURL else { throw Failure.unsafe }
        let directory = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard directory.isDirectory == true, directory.isSymbolicLink != true else { throw Failure.unsafe }
        var data = Data()
        // This bounded metadata read is also needed in a canceled job's defer.
        // Source/media reads remain cancellable; cancellation must not erase the history view.
        try RetainedMediaReader.read(folder.appendingPathComponent("job.json"), maximumBytes: Int64(maximumRecoveryBytes), cancellable: false) {
            data.append($0)
        }
        return data
    }
}
