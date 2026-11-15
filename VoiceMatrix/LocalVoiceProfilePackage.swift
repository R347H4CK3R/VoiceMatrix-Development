import Foundation

/// Builds a reference profile for the existing F5/OpenVoice library, not a trained model.
enum LocalVoiceProfilePackage {
    enum Failure: LocalizedError {
        case metadata, audio, destination, digest
        var errorDescription: String? {
            switch self {
            case .metadata: return "Enter a name (1–80 characters), the exact spoken words (1–2,000 characters), and confirm permission to use the recording."
            case .audio: return "Use a clear, audible recording between half a second and 15 seconds long."
            case .destination: return "The temporary voice folder could not be created. Existing voices were kept."
            case .digest: return "The recording could not be verified."
            }
        }
    }
    struct Profile: Codable, Sendable {
        let id, name, source, permission, referenceText: String
        let schemaVersion: Int
        let kind, engine, referenceFile, referenceSHA256: String
        let trainedModel: Bool
        let categories: [String]
        let referenceBytes: Int
        let seconds: Double
    }
    static func write(wave: Data, name: String, transcript: String, permissionConfirmed: Bool,
                      directory: URL, digest: (Data) throws -> String) throws -> Profile {
        try Task.checkCancellation()
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        let text=transcript.trimmingCharacters(in:.whitespacesAndNewlines)
        guard (1...80).contains(name.count), !name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),
              (1...2000).contains(text.count), permissionConfirmed else {throw Failure.metadata}
        // Canonical PCM16 WAV emitted by LocalVideoAudio; never infer sample metadata.
        guard (24044...720044).contains(wave.count) else {throw Failure.audio}
        let b=[UInt8](wave)
        func n(_ p:Int,_ count:Int)->Int {(0..<count).reduce(0){$0 | Int(b[p+$1]) << (8*$1)}}
        func tag(_ p:Int)->String {String(bytes:b[p..<p+4],encoding:.ascii) ?? ""}
        guard tag(0)=="RIFF",n(4,4)==wave.count-8,tag(8)=="WAVE",tag(12)=="fmt ",
              n(16,4)==16,n(20,2)==1,n(22,2)==1,n(24,4)==24000,n(28,4)==48000,
              n(32,2)==2,n(34,2)==16,tag(36)=="data",n(40,4)==wave.count-44,
              (wave.count-44)%2==0 else {throw Failure.audio}
        var energy=0.0
        for p in stride(from:44,to:b.count,by:2) {
            let value=Double(Int16(bitPattern:UInt16(n(p,2))))/32768
            energy+=value*value
        }
        guard sqrt(energy/Double((wave.count-44)/2))>=0.0002 else {throw Failure.audio}
        let hash=try digest(wave)
        guard hash.count==64,hash.allSatisfy({"0123456789abcdef".contains($0)}) else {throw Failure.digest}
        try Task.checkCancellation()
        let fm=FileManager.default
        guard directory.isFileURL,!fm.fileExists(atPath:directory.path) else {throw Failure.destination}
        try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var accepted=false
        defer {if !accepted {try? fm.removeItem(at:directory)}}
        let id="local-"+UUID().uuidString.lowercased()
        let profile=Profile(id:id,name:name,source:"User-provided recording on this device; transcript entered by user",
            permission:"User confirmed permission to use this voice recording",referenceText:text,schemaVersion:1,
            kind:"f5-reference",engine:"F5TTS_v1_Base",referenceFile:"reference.wav",referenceSHA256:hash,
            trainedModel:false,categories:["Local","User reference","Unverified resemblance"],referenceBytes:wave.count,
            seconds:Double(wave.count-44)/48000)
        let folder=directory.appendingPathComponent(id,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        for (file,data) in [("reference.wav",wave),("manifest.json",try JSONEncoder().encode(profile))] {
            try Task.checkCancellation()
            let url=folder.appendingPathComponent(file)
            try data.write(to:url,options:.atomic)
            try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        }
        try Task.checkCancellation()
        let collection=try JSONSerialization.data(withJSONObject:["schemaVersion":1,"voices":[["id":id,"folder":id]]],options:.sortedKeys)
        try collection.write(to:directory.appendingPathComponent("collection.json"),options:.atomic)
        try Task.checkCancellation()
        accepted=true
        return profile
    }
}
