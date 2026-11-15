import Foundation

/// Container admission only. LocalVideoAudio still validates actual decodability,
/// one audio track, duration, decoded PCM, clipping and timeline coverage.
enum LocalMediaImportPolicy {
    enum Failure: LocalizedError {
        case unsupported
        var errorDescription: String? {
            "Choose a local MP4, MOV, M4V, WAV, M4A, AAC, CAF, MP3 or AIFF file. This container is unsupported; no source or existing voice was changed."
        }
    }
    static func fileExtension(_ source: URL) throws -> String {
        let ext = source.pathExtension.lowercased()
        guard source.isFileURL,
              ["mp4", "mov", "m4v", "wav", "m4a", "aac", "caf", "mp3", "aif", "aiff"].contains(ext)
        else { throw Failure.unsupported }
        return ext
    }
}
