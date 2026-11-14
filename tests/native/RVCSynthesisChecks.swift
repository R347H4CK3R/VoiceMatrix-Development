import Foundation
@main struct Checks {
 static func main() throws {
  var input=RVCSynthesisInputs(phone:[Float](repeating:0,count:922*768),pitch:[Int64](repeating:1,count:922),pitchHz:[Float](repeating:0,count:922),latentNoise:[Float](repeating:0,count:922*192),phaseNoise:0.5,excitationNoise:[Float](repeating:0,count:368800))
  try input.validate()
  let tensors=try input.tensors()
  precondition(tensors.count==8)
  precondition(tensors["phone"]!.shape == [1,922,768])
  precondition(tensors["pitch"]!.bytes.count==7376)
  precondition(tensors["lengths"]!.bytes.withUnsafeBytes { $0.loadUnaligned(as:Int64.self) } == 922)
  precondition(tensors["speaker"]!.bytes.withUnsafeBytes { $0.loadUnaligned(as:Int64.self) } == 0)
  let original=input
  func rejected(_ value:RVCSynthesisInputs) -> Bool { do { try value.validate();return false } catch {return true} }
  input.phone.removeLast();precondition(rejected(input));input=original
  input.pitch[0]=256;precondition(rejected(input));input=original
  input.pitchHz[0] = .nan;precondition(rejected(input));input=original
  input.phaseNoise=1;precondition(rejected(input));input=original
  input.latentNoise[0] = .infinity;precondition(rejected(input));input=original
  input.excitationNoise=[];precondition(rejected(input))
  try RVCSynthesisAssets.validateManifest(RVCSynthesisAssets.Manifest(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:RVCSynthesisAssets.verifiedSHA256,bytes:110600000))
  for file in ["../synthesizer.onnx","/synthesizer.onnx","other.onnx"] {
   do { try RVCSynthesisAssets.validateManifest(.init(schemaVersion:1,profile:"rvc-v2-922-cpu",file:file,sha256:RVCSynthesisAssets.verifiedSHA256,bytes:110600000));fatalError("unsafe asset accepted") } catch {}
  }
  for size in [0,134217729] {
   do { try RVCSynthesisAssets.validateManifest(.init(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:RVCSynthesisAssets.verifiedSHA256,bytes:size));fatalError("size accepted") } catch {}
  }
  do { try RVCSynthesisAssets.validateManifest(.init(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:String(repeating:"0",count:64),bytes:100));fatalError("untrusted hash") } catch {}

  let fm=FileManager.default
  let root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false)
  defer { try? fm.removeItem(at:root) }
  let pack=root.appendingPathComponent("pack");let cache=root.appendingPathComponent("cache")
  try fm.createDirectory(at:pack,withIntermediateDirectories:false);try fm.createDirectory(at:cache,withIntermediateDirectories:false)
  let bytes=Data(repeating:42,count:1048583)
  try bytes.write(to:pack.appendingPathComponent("synthesizer.onnx"))
  let manifest=RVCSynthesisAssets.Manifest(schemaVersion:1,profile:"rvc-v2-922-cpu",file:"synthesizer.onnx",sha256:RVCSynthesisAssets.verifiedSHA256,bytes:bytes.count)
  try JSONEncoder().encode(manifest).write(to:pack.appendingPathComponent("manifest.json"))
  var blocks:[Int]=[]
  // Digest callbacks here test snapshot I/O; real SHA256 is exercised by the iOS adapter.
  let saved=try RVCSynthesisAssets.snapshot(root:pack,cache:cache,update:{blocks.append($0.count)},finish:{RVCSynthesisAssets.verifiedSHA256})
  let copied=try Data(contentsOf:saved);precondition(copied==bytes)
  precondition(blocks == [1048576,7])
  try fm.removeItem(at:saved.deletingLastPathComponent())
  do { _=try RVCSynthesisAssets.snapshot(root:pack,cache:cache,update:{_ in},finish:{"wrong"});fatalError("digest mismatch accepted") } catch {}
  let remaining=try fm.contentsOfDirectory(atPath:cache.path);precondition(remaining.isEmpty)
  try fm.removeItem(at:pack.appendingPathComponent("synthesizer.onnx"))
  try fm.createSymbolicLink(at:pack.appendingPathComponent("synthesizer.onnx"),withDestinationURL:root.appendingPathComponent("missing"))
  do { _=try RVCSynthesisAssets.snapshot(root:pack,cache:cache,update:{_ in},finish:{RVCSynthesisAssets.verifiedSHA256});fatalError("linked model accepted") } catch {}

  try RVCSynthesisAssets.validateManifest(.init(schemaVersion:1,profile:"hubert-147680-cpu",file:"hubert.onnx",sha256:"980f264a909ff3d85d513e924304b1c179ff5d17280dda0b011ec01cb366aa68",bytes:377647665))
  print("Native tensor and asset admission checks passed")
 }
}
