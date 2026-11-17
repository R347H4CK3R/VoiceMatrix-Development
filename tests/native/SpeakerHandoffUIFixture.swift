import Foundation
import CryptoKit

/// Host-only synthetic fixture generator. Never linked into an app target.
@main enum SpeakerHandoffUIFixture {
    static func main() async throws {
        let fm = FileManager.default
        guard CommandLine.arguments.count == 2 else { fatalError("Pass a new fixture output directory") }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !fm.fileExists(atPath: output.path) else { fatalError("Refusing existing fixture destination") }
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let source = output.appendingPathComponent("synthetic-import", isDirectory: true)
        let support = output.appendingPathComponent("Application Support", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let id = UUID(uuidString: "AB16AB16-0000-4000-8000-000000000016")!
        let jobFolder = support.appendingPathComponent("LocalVideoStudio/" + id.uuidString.lowercased())
        try fm.createDirectory(at: jobFolder, withIntermediateDirectories: true)
        func json(_ value: Any, _ path: URL) throws { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: path) }
        func wave(_ frequency: Int) -> Data {
            var d = Data()
            func tag(_ s: String) { d.append(contentsOf: s.utf8) }
            func number(_ n: Int, _ size: Int) { for i in 0..<size { d.append(UInt8((n >> (i*8)) & 255)) } }
            let count = 72_000
            tag("RIFF"); number(36 + count*2,4); tag("WAVEfmt "); number(16,4)
            number(1,2); number(1,2); number(24_000,4); number(48_000,4); number(2,2); number(16,2)
            tag("data"); number(count*2,4)
            for i in 0..<count { number((i / frequency) % 2 == 0 ? 1000 : 64536,2) }
            return d
        }
        var entries = [[String:String]](), assets = [String:Any](), voices = [String:String](), outcomes = [String:String]()
        for (speaker, name, frequency) in [("one","Synthetic Handoff Alpha",40),("two","Synthetic Handoff Beta",60)] {
            let voice = "synthetic-handoff-" + speaker, folder = source.appendingPathComponent(voice)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let bytes = wave(frequency), hash = SHA256.hash(data: bytes).map { String(format: "%02x",$0) }.joined()
            let profile = CharacterReference(id: voice, name: name, source: "Synthetic tone, not human speech", permission: "Generated test-only fixture", referenceText: "Synthetic fixture for navigation only, not speech quality.", schemaVersion: 1, kind: "f5-reference", engine: "F5TTS_v1_Base", referenceFile: "reference.wav", referenceSHA256: hash, trainedModel: false, categories: ["Synthetic UI fixture"], referenceBytes: bytes.count, seconds: 3)
            try JSONEncoder().encode(profile).write(to: folder.appendingPathComponent("manifest.json"))
            try bytes.write(to: folder.appendingPathComponent("reference.wav"))
            let reference = "reference-"+speaker+".wav", preview = "preview-"+speaker+".wav"
            try bytes.write(to: jobFolder.appendingPathComponent(reference)); try bytes.write(to: jobFolder.appendingPathComponent(preview))
            entries.append(["id":voice,"folder":voice]); voices[speaker]=voice
            outcomes[speaker]="Synthetic saved result for navigation only. No inference or likeness evidence."
            assets[speaker] = ["voiceID":voice,"referenceFile":reference,"referenceSHA256":hash,"previewFile":preview,"previewSHA256":hash]
        }
        try json(["schemaVersion":1,"voices":entries],source.appendingPathComponent("collection.json"))
        let store = CharacterFolderStore(root: support.appendingPathComponent("CharacterReferences"))
        let imported = try await store.importCollection(at: source)
        guard imported.count == 2, try await store.profiles().count == 2 else { fatalError("Fixture import failed") }
        try json(["id":id.uuidString,"created":Date().timeIntervalSinceReferenceDate,"updated":Date().timeIntervalSinceReferenceDate,"stage":"Synthetic saved results","message":"Synthetic navigation fixture; not model output.","completed":true,"events":[],"voiceID":"synthetic-handoff-one","speakerVoiceIDs":voices,"speakerAssets":assets,"speakerOutcomes":outcomes],jobFolder.appendingPathComponent("job.json"))
        print("Generated two synthetic profiles using production CharacterFolderStore import; no inference")
    }
}
