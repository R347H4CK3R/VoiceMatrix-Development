import Foundation

/// Integrity provenance only. It does not identify a speaker or confirm likeness.
struct MatroskaSourceLineage: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let jobID: UUID
    let attemptID: UUID
    let acquisitionSHA256: String
    let mkvSHA256: String
    let derivedSHA256: String

    var isValid: Bool {
        let hashes = [acquisitionSHA256, mkvSHA256, derivedSHA256]
        return schemaVersion == 1 && Set(hashes).count == 3 && hashes.allSatisfy {
            $0.utf8.count == 64 && $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
        }
    }
}

struct MatroskaClipLineage: Codable, Equatable, Sendable {
    let source: MatroskaSourceLineage
    let clipID: UUID
    let clipReceiptSHA256: String
    let clipSHA256: String
    let requestedStart: Double
    let requestedSeconds: Double
    let actualStart: Double
    let frames: Int

    func valid(inputSHA256: String, frames count: Int) -> Bool {
        source.isValid && Self.digest(clipReceiptSHA256) && Self.digest(clipSHA256) &&
        clipSHA256 == inputSHA256 && frames == count && (1...441_000).contains(frames) &&
        requestedStart.isFinite && requestedStart >= 0 && requestedSeconds.isFinite &&
        (0.5...10).contains(requestedSeconds) && requestedStart + requestedSeconds <= 1800 &&
        actualStart.isFinite && actualStart >= 0 && abs(actualStart - requestedStart) <= 1.0 / 44_100 + 1e-9 &&
        actualStart + Double(frames) / 44_100 <= 1800 &&
        abs(Double(frames) - requestedSeconds * 44_100) <= 1.5
    }

    static func digest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }
}

struct MatroskaSeparatedLineage: Codable, Equatable, Sendable {
    let clip: MatroskaClipLineage
    let vocalsSHA256: String

    func valid(sourceSHA256: String) -> Bool {
        MatroskaClipLineage.digest(vocalsSHA256) && vocalsSHA256 != clip.clipSHA256 &&
        vocalsSHA256 == sourceSHA256 && clip.valid(inputSHA256: clip.clipSHA256, frames: clip.frames)
    }
}

struct MatroskaReferenceLineage: Codable, Equatable, Sendable {
    let source: MatroskaSourceLineage
    let requestedStartSeconds: Double
    let requestedDurationSeconds: Double
    let retainedFrames: Int
    let sampleRate: Int
    let referenceSHA256: String
    var separatedClip: MatroskaClipLineage? = nil
    var vocalsSHA256: String? = nil

    func valid(seconds: Double, sha256: String) -> Bool {
        guard source.isValid, requestedStartSeconds.isFinite, requestedStartSeconds >= 0,
              requestedDurationSeconds.isFinite, (0.5...10).contains(requestedDurationSeconds),
              requestedStartSeconds + requestedDurationSeconds <= 1800,
              sampleRate == 24_000, (10_800...240_000).contains(retainedFrames),
              seconds.isFinite, referenceSHA256 == sha256, sha256.utf8.count == 64,
              sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { return false }
        if let clip = separatedClip, let vocalsSHA256 {
            guard clip.source == source, MatroskaSeparatedLineage(clip: clip, vocalsSHA256: vocalsSHA256).valid(sourceSHA256: vocalsSHA256),
                  requestedStartSeconds >= clip.actualStart,
                  requestedStartSeconds + requestedDurationSeconds <= clip.actualStart + Double(clip.frames) / 44_100 + 1e-9 else { return false }
        } else if separatedClip != nil || vocalsSHA256 != nil { return false }
        return abs(Double(retainedFrames) / Double(sampleRate) - seconds) < 0.000001 &&
               abs(Double(retainedFrames) - requestedDurationSeconds * 24_000) <= 1_200
    }
}
