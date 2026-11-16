import Foundation
import CryptoKit

@main struct UnpaddedFinalProbe {
    struct Item: Codable { let voiceID, file, sha256, expected: String }
    struct Outcome: Codable {
        let voiceID, file, expected: String
        let inputSHA256: String?
        let actual: String?
        let wordErrorRate: Double?
        let evidence: OnDeviceTranscription.Evidence?
        let error: String?
        let accepted: Bool
    }
    enum Failure: Error { case arguments, identity, verification }
    static func hash(_ file: URL) throws -> String {
        let v = try file.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true, let size = v.fileSize, (44...8_388_608).contains(size) else { throw Failure.identity }
        return SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x",$0) }.joined()
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 3 else { throw Failure.arguments }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let bundle = URL(fileURLWithPath: CommandLine.arguments[2])
        let out = root.appendingPathComponent("unpadded-verification")
        let items = try JSONDecoder().decode([Item].self,from: Data(contentsOf: out.appendingPathComponent("inputs.json")))
        guard items.count == 2, Set(items.map(\.voiceID)).count == 2, Set(items.map(\.file)).count == 2 else { throw Failure.identity }
        var outcomes: [Outcome] = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        for item in items {
            var actual: String?, evidence: OnDeviceTranscription.Evidence?, digest: String?, wer: Double?, failure: String?
            do {
                guard item.file.range(of: "^[A-Za-z0-9_-]+\\.wav$",options: .regularExpression) != nil,
                      item.sha256.range(of: "^[a-f0-9]{64}$",options: .regularExpression) != nil,
                      item.expected == "Please close the window and bring the notebook." else { throw Failure.identity }
                let file = root.appendingPathComponent("work").appendingPathComponent(item.file)
                digest = try hash(file); guard digest == item.sha256 else { throw Failure.identity }
                let recognizer = OnDeviceTranscription(bundle: bundle)
                let words = try await recognizer.transcribe(file)
                actual = words; evidence = recognizer.lastEvidence
                wer = LocalStudioEvidence.wordErrorRate(expected: item.expected,actual: words)
                guard try hash(file) == item.sha256, evidence?.inputSHA256 == item.sha256 else { throw Failure.identity }
            } catch { failure = String(describing: error) }
            outcomes.append(Outcome(voiceID:item.voiceID,file:item.file,expected:item.expected,inputSHA256:digest,actual:actual,wordErrorRate:wer,evidence:evidence,error:failure,accepted:failure == nil && wer == 0))
            try encoder.encode(outcomes).write(to: out.appendingPathComponent("outcomes.json"),options: .atomic)
        }
        guard outcomes.count == 2, outcomes.allSatisfy({ $0.accepted && $0.wordErrorRate == 0 }) else { throw Failure.verification }
        print("Both exact final WAVs passed pinned build10 baseline ASR with zero word errors. Not physical device or likeness verification.")
    }
}
