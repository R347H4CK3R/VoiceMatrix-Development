import Foundation
import CryptoKit
@main struct Probe {
    struct Fixture: Decodable { let audioSHA256:String }
    static func main() async throws {
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
