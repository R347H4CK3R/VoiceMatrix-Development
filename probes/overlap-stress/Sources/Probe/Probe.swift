import Foundation
import CryptoKit
@main struct Probe {
 struct Screening: Codable {
  let speaker:String;let start:Double;let end:Double
  let referenceFile:String?;let referenceSHA256:String?;let evidence:LocalSoundQuality.Evidence?;let error:String?
 }
 static func main() async throws {
  let audio=URL(fileURLWithPath:CommandLine.arguments[2]);let expected=CommandLine.arguments[3]
  func hash() throws -> String { SHA256.hash(data:try Data(contentsOf:audio)).map{String(format:"%02x",$0)}.joined() }
  guard try hash()==expected else {fatalError("Fixture checksum mismatch")}
  let analysis=try await LocalSpeakerDiarization.analyze(source:audio,bundle:URL(fileURLWithPath:CommandLine.arguments[1])) { print($0) }
  _ = try LocalSpeakerDiarization.validatedForCurrentPolicy(analysis)
  guard analysis.selectionPolicyVersion == 5, analysis.rawOverlap?.sourceSHA256 == expected else { fatalError("Missing current source-bound overlap evidence") }
  guard try hash()==expected else {fatalError("Original fixture changed")}
  let output=URL(fileURLWithPath:CommandLine.arguments[4])
  try JSONEncoder().encode(analysis).write(to:output)
  let candidates = try LocalSpeakerPolicy.speakerWindows(analysis.segments,duration:analysis.seconds,candidateLimit:6)
  let before = candidates.reduce(0) { $0 + $1.windows.count }
  let after = analysis.speakerWindows.reduce(0) { $0 + $1.windows.count }
  let summary: [String: Any] = ["sourceSHA256":expected,"candidates":before,"retained":after,"excluded":before-after]
  try JSONSerialization.data(withJSONObject:summary).write(to:output.deletingPathExtension().appendingPathExtension("guard.json"))

  var screenings:[Screening]=[]
  let receipt=output.deletingPathExtension().appendingPathExtension("screening.json")
  for group in analysis.speakerWindows {
   for (index,window) in group.windows.enumerated() {
    var referenceHash:String?=nil;var referenceFile:String?=nil
    do {
     let clip=try await LocalVideoAudio.extract(source:audio,start:window.start,seconds:window.seconds)
     let reference=output.deletingPathExtension().appendingPathExtension(group.speaker+"-"+String(index)+".wav")
     try clip.wave.write(to:reference,options:.withoutOverwriting)
     referenceFile=reference.lastPathComponent
     referenceHash=SHA256.hash(data:clip.wave).map{String(format:"%02x",$0)}.joined()
     let evidence=try await LocalSoundQuality.analyze(source:reference) { print($0) }
     guard evidence.sourceSHA256==referenceHash else {fatalError("Screening hash mismatch")}
     screenings.append(Screening(speaker:group.speaker,start:window.start,end:window.end,referenceFile:referenceFile,referenceSHA256:referenceHash,evidence:evidence,error:nil))
    } catch {
     screenings.append(Screening(speaker:group.speaker,start:window.start,end:window.end,referenceFile:referenceFile,referenceSHA256:referenceHash,evidence:nil,error:String(describing:error)))
    }
    try JSONEncoder().encode(screenings).write(to:receipt,options:.atomic)
   }
  }
  if screenings.isEmpty {try JSONEncoder().encode(screenings).write(to:receipt,options:.atomic)}
  guard try hash()==expected else {fatalError("Source changed after screening")}

 }
}
