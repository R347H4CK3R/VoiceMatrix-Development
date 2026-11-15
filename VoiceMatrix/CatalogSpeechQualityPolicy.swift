import Foundation

enum CatalogSpeechQualityPolicy {
    static func accepts(expected: String, actual: String, audioHash: String, evidenceAudioHash: String,
                        transcriptHash: String, evidenceTranscriptHash: String) -> Bool {
        let validHash = { (value: String) in value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
        guard validHash(audioHash), validHash(transcriptHash), audioHash == evidenceAudioHash,
              transcriptHash == evidenceTranscriptHash, LocalStudioEvidence.usableTranscript(actual),
              !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let rate = LocalStudioEvidence.wordErrorRate(expected: expected, actual: actual)
        return rate.isFinite && rate >= 0 && rate <= 0.1
    }
}
