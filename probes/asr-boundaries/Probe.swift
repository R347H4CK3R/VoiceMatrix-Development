import Foundation
import CryptoKit
@main struct Probe {
 @MainActor static func main() async throws {
  let resources=URL(fileURLWithPath:CommandLine.arguments[1]),root=URL(fileURLWithPath:CommandLine.arguments[2])
  let output=URL(fileURLWithPath:CommandLine.arguments[3])
  let files=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  var rows:[[String:Any]]=[]
  for file in files {
   let sha=SHA256.hash(data:try Data(contentsOf:file)).map{String(format:"%02x",$0)}.joined()
   let asr=OnDeviceTranscription(bundle:resources)
   var row:[String:Any] = ["file":file.lastPathComponent,"sha256":sha]
   do {
    let text=try await asr.transcribe(file)
    row["text"]=text;row["wordErrorRate"]=LocalStudioEvidence.wordErrorRate(expected:"Please close the window and bring the notebook.",actual:text)
    row["accepted"]=true;if let detail=asr.lastEvidence { row["meanTokenConfidence"]=detail.meanTokenConfidence }
   } catch {row["accepted"]=false;row["error"]=String(describing:error)}
   rows.append(row)
   try JSONSerialization.data(withJSONObject:rows,options:[.prettyPrinted,.sortedKeys]).write(to:output,options:.atomic)
   print(String(data:try JSONSerialization.data(withJSONObject:row,options:[.sortedKeys]),encoding:.utf8)!)
  }
 }
}
