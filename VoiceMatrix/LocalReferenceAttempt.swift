import Foundation

/// Durable candidate-level evidence. Speaker labels are diarization labels, not identities.
struct LocalReferenceAttempt: Codable, Sendable {
    enum Failure: Error {case invalid, terminal, changed}
    enum Outcome: String, Codable, Sendable {
        case selected, extracted, transcribed, generating, verifying
        case extractionRejected, screeningRejected, referenceNoSpeech, referenceIncompatible
        case generationRejected, previewNoSpeech, previewWordsRejected, saved, reused
        var terminal: Bool {
            switch self {case .selected,.extracted,.transcribed,.generating,.verifying:return false;default:return true}
        }
    }
    struct Event: Codable, Equatable, Sendable {
        let date: Date
        let outcome: Outcome
        let reason: String
        let referenceSHA256, previewSHA256, voiceID: String?
    }
    let schemaVersion: Int
    let id, sourceSHA256, speaker: String
    let start, end: Double
    private(set) var events: [Event]
    private static func hash(_ value:String)->Bool {
        value.count==64 && value.allSatisfy({"0123456789abcdef".contains($0)})
    }
    init(sourceSHA256:String,speaker:String,start:Double,end:Double) throws {
        guard Self.hash(sourceSHA256),speaker.range(of:"^[A-Za-z0-9_-]{1,40}$",options:.regularExpression) != nil,
              start.isFinite,end.isFinite,start>=0,end<=1800,(3...15).contains(end-start) else {throw Failure.invalid}
        schemaVersion=1;id=UUID().uuidString.lowercased();self.sourceSHA256=sourceSHA256
        self.speaker=speaker;self.start=start;self.end=end;events=[]
    }
    mutating func record(_ outcome:Outcome,reason:String,referenceSHA256:String?=nil,
                         previewSHA256:String?=nil,voiceID:String?=nil,directory:URL) throws {
        try Task.checkCancellation()
        guard events.last?.outcome.terminal != true else {throw Failure.terminal}
        guard schemaVersion==1,Self.hash(sourceSHA256),events.count<16,(1...500).contains(reason.utf8.count),
              referenceSHA256.map(Self.hash) ?? true,previewSHA256.map(Self.hash) ?? true,
              voiceID.map({$0.range(of:"^[a-z0-9_-]{1,100}$",options:.regularExpression) != nil}) ?? true else {throw Failure.invalid}
        if let original=events.compactMap({$0.referenceSHA256}).first,let referenceSHA256,original != referenceSHA256 {throw Failure.changed}
        if let original=events.compactMap({$0.previewSHA256}).first,let previewSHA256,original != previewSHA256 {throw Failure.changed}
        if outcome == .saved || outcome == .reused {
            guard referenceSHA256 != nil,previewSHA256 != nil,voiceID != nil else {throw Failure.invalid}
        }
        if outcome == .extracted {guard referenceSHA256 != nil else {throw Failure.invalid}}
        let fm=FileManager.default
        let info=try directory.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])
        guard directory.isFileURL,info.isDirectory==true,info.isSymbolicLink != true,
              UUID(uuidString:id) != nil else {throw Failure.invalid}
        let file=directory.appendingPathComponent("candidate-"+id+".json")
        if fm.fileExists(atPath:file.path) {
            let stat=try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard stat.isRegularFile==true,stat.isSymbolicLink != true,(1...65536).contains(stat.fileSize ?? 0) else {throw Failure.changed}
            let previous=try JSONDecoder().decode(Self.self,from:Data(contentsOf:file))
            guard previous.schemaVersion==schemaVersion,previous.id==id,previous.sourceSHA256==sourceSHA256,previous.speaker==speaker,
                  previous.start==start,previous.end==end,previous.events==events else {throw Failure.changed}
        } else {guard events.isEmpty else {throw Failure.changed}}
        var next=self
        next.events.append(Event(date:Date(),outcome:outcome,reason:reason,referenceSHA256:referenceSHA256,previewSHA256:previewSHA256,voiceID:voiceID))
        let data=try JSONEncoder().encode(next)
        guard data.count<=65536 else {throw Failure.invalid}
        try Task.checkCancellation()
        try data.write(to:file,options:.atomic)
        self=next
    }
}
