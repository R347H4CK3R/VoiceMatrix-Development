import Foundation
import CryptoKit
@main struct Probe {
    struct Fixture: Decodable { let audioSHA256:String }
    static func main() async throws {
        // Verify retained-analysis migration through the production adapter.
        let segments: [LocalSpeakerPolicy.Segment] = [.init(speaker:"S1",start:0,end:2),.init(speaker:"S1",start:2.3,end:4.3)]
        for version: Int? in [nil, 1, 2] {
            let oldWindows = try LocalSpeakerPolicy.speakerWindows(segments,duration:4.3,includeFallbacks:(version ?? 1) >= 2,joinSameSpeakerPauses:false)
            let legacy = LocalSpeakerDiarization.Analysis(modelRevision:"df2625ac79a7ac6b65ad868fee6d80f320da4232",seconds:4.3,segments:segments,speakerWindows:oldWindows,selectionPolicyVersion:version)
            let migrated = try LocalSpeakerDiarization.validatedForCurrentPolicy(legacy)
            guard oldWindows[0].windows.isEmpty, migrated.selectionPolicyVersion == 3,
                  migrated.speakerWindows[0].windows.count == 1 else {fatalError("Legacy migration failed")}
            let tampered = LocalSpeakerDiarization.Analysis(modelRevision:legacy.modelRevision,seconds:4.3,segments:segments,speakerWindows:migrated.speakerWindows,selectionPolicyVersion:version)
            do { _ = try LocalSpeakerDiarization.validatedForCurrentPolicy(tampered); fatalError("Tampered legacy crops accepted") }
            catch LocalSpeakerDiarization.Failure.invalidAudio {}
        }
        print("PASS: version 1/2 retained analyses migrate to policy 3 only after exact old-window validation.")
        let models=URL(fileURLWithPath:CommandLine.arguments[1])
        let audio=URL(fileURLWithPath:CommandLine.arguments[2])
        let proof=URL(fileURLWithPath:CommandLine.arguments[3])
        let output=URL(fileURLWithPath:CommandLine.arguments[4])
        let expected=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:proof))
        func hash() throws -> String { SHA256.hash(data:try Data(contentsOf:audio)).map{String(format:"%02x",$0)}.joined() }
        guard try hash()==expected.audioSHA256 else {fatalError("Real speech fixture hash mismatch")}
        try LocalSpeakerDiarization.verify(models)
        let analysis=try await LocalSpeakerDiarization.analyze(source:audio,bundle:models) { print($0) }
        try LocalSpeakerDiarization.validate(analysis)
        guard try hash()==expected.audioSHA256 else {fatalError("Source changed")}
        try JSONEncoder().encode(analysis).write(to:output)
        print("Production CoreML analysis saved. No physical-iPhone or identity claim.")
    }
}
