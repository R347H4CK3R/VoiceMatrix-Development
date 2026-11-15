import Foundation
import CryptoKit
import Metal

/// Controlled experiment only. No production retry or speech trimming.
@main struct ReferencePaddingHoldout {
    struct Attempt: Codable {
        let caseID: Int
        let tailMilliseconds: Int
        let referenceSHA256: String
        let expected: String
        let outputSHA256: String?
        let rawOutputSHA256: String?
        let recognized: String?
        let wordErrorRate: Double?
        let evidence: OnDeviceTranscription.Evidence?
        let accepted: Bool
        let error: String?
        let generationSeconds: Double
        let verificationSeconds: Double
    }
    enum Failure: Error { case arguments, identity }
    static func digest(_ url:URL) throws -> String {
        SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count==4,MTLCreateSystemDefaultDevice() != nil else {throw Failure.arguments}
        let resources=URL(fileURLWithPath:CommandLine.arguments[1])
        let out=URL(fileURLWithPath:CommandLine.arguments[2])
        let commit=CommandLine.arguments[3]
        guard commit.range(of:"^[a-f0-9]{40}$",options:.regularExpression) != nil else {throw Failure.arguments}
        let ref=out.appendingPathComponent("reference.wav")
        guard try digest(ref)=="da2cdba0b9b706dd053fe9e643a941bb99816439ac064a8443f732c6c33270a5" else {throw Failure.identity}
        let refText=try String(contentsOf:out.appendingPathComponent("reference.txt"),encoding:.utf8)
        guard refText=="They were absorbed in his theology and were under the dominion of his name, while that which was truly great." else {throw Failure.identity}
        let texts=["Please close the window and bring the notebook.",
            "The blue bicycle is parked beside the garden gate.",
            "Tomorrow morning we will pack sandwiches and visit the museum."]
        var attempts:[Attempt]=[]
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        for (caseID,expected) in texts.enumerated() {
        for tailMilliseconds in [0,50] {
            let variant=out.appendingPathComponent("reference-tail-\(tailMilliseconds).wav")
            let referenceHash=try digest(variant)
            let engine=F5ReferenceEngine(steps:32,seed:0)
            let dest=out.appendingPathComponent("case-\(caseID)-tail-\(tailMilliseconds).wav")
            let raw=out.appendingPathComponent("case-\(caseID)-tail-\(tailMilliseconds)-raw.wav")
            let started=Date()
            var generated:Double=0,verified:Double=0
            do {
                try await engine.load(localBundle:resources.appendingPathComponent("F5TTS"))
                try await engine.speak(text:expected,referenceAudio:variant,referenceText:refText,
                    destination:raw,preserveIncomplete:true)
                try await SpeechRendering.render(source:raw,destination:dest,controls:SpeechControls())
                generated=Date().timeIntervalSince(started)
                await engine.unload()
                let hash=try digest(dest)
                let recognizer=OnDeviceTranscription(bundle:resources.appendingPathComponent("ParakeetASR"))
                let verificationStart=Date()
                let words=try await recognizer.transcribe(dest)
                verified=Date().timeIntervalSince(verificationStart)
                let wer=LocalStudioEvidence.wordErrorRate(expected:expected,actual:words)
                let accepted=wer<=0.1 && recognizer.lastEvidence?.inputSHA256==hash
                attempts.append(Attempt(caseID:caseID,tailMilliseconds:tailMilliseconds,referenceSHA256:referenceHash,expected:expected,outputSHA256:hash,rawOutputSHA256:try digest(raw),recognized:words,
                    wordErrorRate:wer,evidence:recognizer.lastEvidence,accepted:accepted,error:nil,
                    generationSeconds:generated,verificationSeconds:verified))
            } catch {
                await engine.unload()
                attempts.append(Attempt(caseID:caseID,tailMilliseconds:tailMilliseconds,referenceSHA256:referenceHash,expected:expected,outputSHA256:try? digest(dest),rawOutputSHA256:try? digest(raw),
                    recognized:nil,wordErrorRate:nil,evidence:nil,accepted:false,error:String(describing:error),
                    generationSeconds:generated,verificationSeconds:verified))
            }
            // Preserve every attempt before continuing. No result replaces the original.
            try encoder.encode(attempts).write(to:out.appendingPathComponent("holdout-attempts.json"),options:.atomic)
        }
        }
        print("Controlled same-reference text holdout recorded six attempts; no generalization to other references or devices.")
    }
}
