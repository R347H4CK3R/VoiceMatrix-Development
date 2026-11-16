import Foundation
import CryptoKit

/// Diagnostic only. Expected text is used after recognition, never as an ASR prompt.
@main struct ReferenceContextHoldoutProbe {
    struct Case: Decodable {
        let id, mode, file, sha256, expected, sourceSHA256: String
    }
    struct Manifest: Decodable { let cases: [Case] }
    struct Result: Codable {
        let id, mode, file, inputSHA256, sourceSHA256, expected: String
        let recognized: String?
        let wordErrorRate: Double?
        let evidence: OnDeviceTranscription.Evidence?
        let error: String?
        let elapsedSeconds: Double
        let accepted: Bool
    }
    enum Failure: Error { case arguments, identity, evidence }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 5 else { throw Failure.arguments }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let models = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        let commit = CommandLine.arguments[4]
        guard commit.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil else { throw Failure.arguments }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        guard manifest.cases.count == 8, Set(manifest.cases.map(\.id)).count == 8 else { throw Failure.identity }
        let groups = Dictionary(grouping: manifest.cases, by: \.file)
        guard groups.count == 4, groups.values.allSatisfy({ entries in
            entries.count == 2 && Set(entries.map(\.mode)) == Set(["baseline", "reference"]) &&
            Set(entries.map(\.sha256)).count == 1 && Set(entries.map(\.expected)).count == 1
        }) else { throw Failure.identity }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var results: [Result] = []
        for entry in manifest.cases {
            guard entry.file == URL(fileURLWithPath: entry.file).lastPathComponent,
                  entry.file.hasSuffix(".wav"), !entry.file.contains("\\"),
                  entry.sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw Failure.identity }
            let file = root.appendingPathComponent(entry.file)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure.identity }
            let digest = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256 else { throw Failure.identity }
            let start = Date()
            let recognizer = OnDeviceTranscription(bundle: models)
            var words: String?, wer: Double?, failure: String?
            do {
                guard entry.mode == "baseline" || entry.mode == "reference" else { throw Failure.identity }
                let recognized: String
                if entry.mode == "reference" { recognized = try await recognizer.transcribeReference(file) }
                else { recognized = try await recognizer.transcribe(file) }
                guard recognizer.lastEvidence?.inputSHA256 == digest else { throw Failure.evidence }
                words = recognized
                wer = LocalStudioEvidence.wordErrorRate(expected: entry.expected, actual: recognized)
                let expectedContext: Double? = entry.mode == "reference" ? 0.25 : nil
                guard recognizer.lastEvidence?.referenceLeadingSeconds == expectedContext else { throw Failure.evidence }
            } catch { failure = String(describing: error) }
            results.append(Result(id: entry.id, mode: entry.mode, file: entry.file, inputSHA256: digest,
                sourceSHA256: entry.sourceSHA256, expected: entry.expected, recognized: words,
                wordErrorRate: wer, evidence: recognizer.lastEvidence, error: failure,
                elapsedSeconds: Date().timeIntervalSince(start), accepted: failure == nil && wer == 0))
            try encoder.encode(results).write(to: output, options: .atomic)
        }
        guard results.count == 8, results.allSatisfy({ $0.accepted }) else { throw Failure.evidence }
        // Strict fixture gate only, not general accuracy or device evidence.
        print("All8production-method fixture checks passed WER0 and expected context receipts. No general accuracy or device claim.")
    }
}
