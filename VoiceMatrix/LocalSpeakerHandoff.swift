import Foundation

/// Selection identity only. This does not certify voice identity, likeness or inference quality.
enum LocalSpeakerHandoff {
    struct Identity { let id: String; let referenceSHA256: String }
    static func voiceID(expected: String, referenceSHA256: String, profiles: [Identity]) -> String? {
        guard !expected.isEmpty,
              referenceSHA256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        let matches = profiles.filter { $0.id == expected }
        guard matches.count == 1, matches[0].referenceSHA256 == referenceSHA256 else { return nil }
        return expected
    }
}
