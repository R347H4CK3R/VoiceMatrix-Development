import Foundation
import CryptoKit
@main struct RetainedSpeechDiagnostic {
    enum Failure: Error { case arguments, identity, evidence }
    struct Report: Codable {
        let expected: String
        let actual: String
        let wordErrorRate: Double
        let inputSHA256: String
        let evidenceHashMatches: Bool
        let transcriptionEvidence: OnDeviceTranscription.Evidence?
        let accepted: Bool
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 4 else { throw Failure.arguments }
        let audio=URL(fileURLWithPath:CommandLine.arguments[1])
        let models=URL(fileURLWithPath:CommandLine.arguments[2])
        let out=URL(fileURLWithPath:CommandLine.arguments[3])
        let hash=SHA256.hash(data:try Data(contentsOf:audio)).map{String(format:"%02x",$0)}.joined()
        guard hash=="fe750049af1dc3f52ca50d3d9f6b3411a9154417a7e53b1df26fb687a47e541a" else { throw Failure.identity }
        let expected="Please close the window and bring the notebook."
        let recognizer=OnDeviceTranscription(bundle:models)
        let words: String
        do { words=try await recognizer.transcribe(audio) }
        catch {
            try JSONSerialization.data(withJSONObject:["error":String(describing:error),"inputSHA256":hash],
                options:[.prettyPrinted,.sortedKeys]).write(to:out,options:.atomic)
            throw error
        }
        let wer=LocalStudioEvidence.wordErrorRate(expected:expected,actual:words)
        let matches=recognizer.lastEvidence?.inputSHA256==hash
        let accepted=wer<=0.1 && matches
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        try encoder.encode(Report(expected:expected,actual:words,wordErrorRate:wer,inputSHA256:hash,
            evidenceHashMatches:matches,transcriptionEvidence:recognizer.lastEvidence,accepted:accepted)).write(to:out,options:.atomic)
        print("Retained output WER=\(wer); evidence hash matches=\(matches); accepted=\(accepted)")
        guard accepted else { throw Failure.evidence }
    }
}
