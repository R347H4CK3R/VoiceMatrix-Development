import Foundation
import CryptoKit
import Metal

/// Controlled experiment only. No production retry or speech trimming.
@main struct ReferenceTextDiagnostic {
    struct Attempt: Codable {
        let referenceID: String
        let textFormat: String
        let referenceText: String
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
    struct ReferenceReceipt: Codable {
        let expected:String
        let recognized:String?
        let wordErrorRate:Double?
        let error:String?
        let inputSHA256:String
        let evidence:OnDeviceTranscription.Evidence?
    }
    enum Failure: Error { case arguments, identity }
    static func digest(_ url:URL) throws -> String {
        SHA256.hash(data:try Data(contentsOf:url)).map{String(format:"%02x",$0)}.joined()
    }
    @MainActor static func verifyReference(_ url:URL,expected:String,resources:URL) async throws -> ReferenceReceipt {
        let recognizer=OnDeviceTranscription(bundle:resources.appendingPathComponent("ParakeetASR"))
        let words=try await recognizer.transcribe(url)
        return ReferenceReceipt(expected:expected,recognized:words,wordErrorRate:LocalStudioEvidence.wordErrorRate(expected:expected,actual:words),error:nil,inputSHA256:try digest(url),evidence:recognizer.lastEvidence)
    }
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count==4,MTLCreateSystemDefaultDevice() != nil else {throw Failure.arguments}
        let resources=URL(fileURLWithPath:CommandLine.arguments[1])
        let out=URL(fileURLWithPath:CommandLine.arguments[2])
        let commit=CommandLine.arguments[3]
        guard commit.range(of:"^[a-f0-9]{40}$",options:.regularExpression) != nil else {throw Failure.arguments}
        let expected="Please close the window and bring the notebook."
        var attempts:[Attempt]=[]
        let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
        for referenceID in ["8455-210777-0028","1580-141083-0051"] {
        let referenceRoot=out.appendingPathComponent(referenceID)
        let originalText=try String(contentsOf:referenceRoot.appendingPathComponent("reference.txt"),encoding:.utf8)
        let formattedText=referenceID=="8455-210777-0028" ? "Jack would become Eva's happy husband and would remain amidst the hurried duties of the eager world." : "Only for a minute or so."
        guard LocalStudioEvidence.wordErrorRate(expected:originalText,actual:formattedText)==0 else {throw Failure.identity}
        let refURL=referenceRoot.appendingPathComponent("reference.wav")
        do {
            let referenceReceipt=try await verifyReference(refURL,expected:originalText,resources:resources)
            try encoder.encode(referenceReceipt).write(to:out.appendingPathComponent(referenceID+"-reference-receipt.json"),options:.atomic)
        } catch {
            let failed=ReferenceReceipt(expected:originalText,recognized:nil,wordErrorRate:nil,error:String(describing:error),inputSHA256:try digest(refURL),evidence:nil)
            try encoder.encode(failed).write(to:out.appendingPathComponent(referenceID+"-reference-receipt.json"),options:.atomic)
            throw error
        }
        for textFormat in ["original","sentence"] {
            let refText=textFormat=="original" ? originalText : formattedText
            let variant=referenceRoot.appendingPathComponent("reference.wav")
            let referenceHash=try digest(variant)
            let engine=F5ReferenceEngine(steps:32,seed:0)
            let dest=out.appendingPathComponent("\(referenceID)-\(textFormat).wav")
            let raw=out.appendingPathComponent("\(referenceID)-\(textFormat)-raw.wav")
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
                attempts.append(Attempt(referenceID:referenceID,textFormat:textFormat,referenceText:refText,referenceSHA256:referenceHash,expected:expected,outputSHA256:hash,rawOutputSHA256:try digest(raw),recognized:words,
                    wordErrorRate:wer,evidence:recognizer.lastEvidence,accepted:accepted,error:nil,
                    generationSeconds:generated,verificationSeconds:verified))
            } catch {
                await engine.unload()
                attempts.append(Attempt(referenceID:referenceID,textFormat:textFormat,referenceText:refText,referenceSHA256:referenceHash,expected:expected,outputSHA256:try? digest(dest),rawOutputSHA256:try? digest(raw),
                    recognized:nil,wordErrorRate:nil,evidence:nil,accepted:false,error:String(describing:error),
                    generationSeconds:generated,verificationSeconds:verified))
            }
            // Preserve every attempt before continuing. No result replaces the original.
            try encoder.encode(attempts).write(to:out.appendingPathComponent("format-attempts.json"),options:.atomic)
        }
        }
        print("Independent reference comparison recorded four attempts; no broad validation or device proof.")
    }
}
