import Foundation
import CryptoKit
@main struct Checks {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let wave=try Data(contentsOf:root.appendingPathComponent("reference.wav"))
  let text=String(data:try Data(contentsOf:root.appendingPathComponent("transcript.txt")),encoding:.utf8)!
  func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
  let package=root.appendingPathComponent("package")
  let created=try LocalVoiceProfilePackage.write(wave:wave,name:"LibriSpeech reference test",transcript:text,permissionConfirmed:true,directory:package,digest:hash)
  let store=CharacterFolderStore(root:root.appendingPathComponent("library"))
  let profiles=try await store.importCollection(at:package)
  guard let saved=profiles.first(where:{$0.id==created.id}) else {fatalError("profile missing")}
  let url=try await store.referenceURL(id:saved.id)
  let loaded=try Data(contentsOf:url)
  precondition(saved.referenceText==text && hash(loaded)==created.referenceSHA256)
  let words="This is a separate test sentence."
  let chunks=try F5SpeechChunks.plan(text:words,referenceText:saved.referenceText,referenceSeconds:saved.seconds)
  precondition(chunks.joined(separator:" ")==words)
  let report:[String:Any]=["engine":saved.engine,"trainedModel":saved.trainedModel,"seconds":saved.seconds,
    "referenceSHA256":saved.referenceSHA256,"referenceText":saved.referenceText,"plannedText":words,"chunks":chunks,
    "libraryRoundtripPassed":true,"neuralInferenceRun":false,"physicalIPhoneVerified":false]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("result.json"))
  print("Real speech reference retained its exact transcript and passed actual F5 planning")
 }
}
