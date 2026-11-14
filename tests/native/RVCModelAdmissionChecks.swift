import Foundation
@main struct Checks {
 static func main() throws {
  let candidate=RVCSynthesisAssets.Manifest(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:"f7519d6f3c248f6eb2acabd11352e0abf91515a7e95662fdb23a5b1f1e009dcc",bytes:110560512)
  try RVCSynthesisAssets.validateManifest(candidate)
  let name=try RVCSynthesisAssets.voiceName(candidate);precondition(name=="VCTK p226 · evaluation")
  try RVCSynthesisAssets.validateRetrievalPair(candidate,usesRetrieval:false)
  do {try RVCSynthesisAssets.validateRetrievalPair(candidate,usesRetrieval:true);fatalError("Wrong voice index accepted")} catch {}
  let baseline=RVCSynthesisAssets.Manifest(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:RVCSynthesisAssets.verifiedSHA256,bytes:110560512)
  try RVCSynthesisAssets.validateRetrievalPair(baseline,usesRetrieval:true)
  let unknown=RVCSynthesisAssets.Manifest(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:String(repeating:"a",count:64),bytes:110560512)
  do {try RVCSynthesisAssets.validateManifest(unknown);fatalError("Unknown model accepted")} catch {}
  print("Candidate accepted only by pinned digest; wrong retrieval pair rejected; baseline preserved")
 }
}
