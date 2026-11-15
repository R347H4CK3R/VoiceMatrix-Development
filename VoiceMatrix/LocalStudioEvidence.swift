import Foundation

/// Intelligibility evidence is not speaker identity, diarization or likeness proof.
enum LocalStudioEvidence {
    /// PCM16 mono output at 24 kHz must cover the requested reference interval.
    /// Fifty milliseconds allows codec-frame rounding, not missing speech.
    static func referenceCoversInterval(frames: Int, requestedSeconds: Double) -> Bool {
        guard (10_800...360_000).contains(frames), requestedSeconds.isFinite,
              (0.5...15).contains(requestedSeconds) else { return false }
        return abs(Double(frames) - requestedSeconds * 24_000) <= 1_200
    }
    /// Keep decoded samples aligned with the selected source timestamps.
    static func referenceTimestampMatches(timestamp: Double, start: Double, decodedFrames: Int) -> Bool {
        guard timestamp.isFinite, start.isFinite, (0...1800).contains(start),
              (0...360_000).contains(decodedFrames) else { return false }
        return abs(timestamp - (start + Double(decodedFrames) / 24_000)) <= 0.05
    }
    static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    static func usableTranscript(_ text: String) -> Bool {
        let count = words(text).count
        return (3...100).contains(count) && text.utf8.count <= 700 &&
            !text.contains("♪") && !text.contains("♫") && !text.contains("[") && !text.contains("]")
    }
    static func wordErrorRate(expected: String, actual: String) -> Double {
        let a = words(expected), b = words(actual)
        guard !a.isEmpty, a.count <= 200, b.count <= 200 else { return 1 }
        var row = Array(0...b.count)
        for (i, word) in a.enumerated() {
            var next = [i + 1]
            for (j, other) in b.enumerated() { next.append(min(next[j] + 1, row[j + 1] + 1, row[j] + (word == other ? 0 : 1))) }
            row = next
        }
        return Double(row[b.count]) / Double(a.count)
    }
    static func windows(duration: Double) -> [(start: Double, seconds: Double)] {
        guard duration.isFinite, duration >= 3, duration <= 1800 else { return [] }
        return stride(from: 0.0, through: max(0, duration - 3), by: 6).map { ($0, min(8, duration - $0)) }
    }
}
