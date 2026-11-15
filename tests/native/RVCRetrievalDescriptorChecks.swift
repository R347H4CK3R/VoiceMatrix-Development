import Foundation
@main struct Checks {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),manifest=root.appendingPathComponent("manifest.json")
  let legacy=try RVCRetrievalAssets.descriptor(at:root)
  precondition(legacy.profile==RVCRetrievalAssets.diagnosticProfile)
  for text in ["{}", "{\"schemaVersion\":2,\"profile\":\"vctk-p226-ivf1161\"}", "{\"schemaVersion\":1,\"profile\":\"unknown\"}", String(repeating:" ",count:4097)] {
   try Data(text.utf8).write(to:manifest)
   do {_=try RVCRetrievalAssets.descriptor(at:root);fatalError("Malformed manifest admitted")} catch {}
  }
  let forged="{\"schemaVersion\":1,\"profile\":\"vctk-p226-ivf1161\",\"sha256\":\"attacker\",\"file\":\"../outside\"}"
  try Data(forged.utf8).write(to:manifest)
  let known=try RVCRetrievalAssets.descriptor(at:root)
  precondition(known.files.map{$0.name}==["centroids.f32","vectors.f32","lists.json"])
  precondition(known.files[1].bytes==139201536 && known.files[1].sha256=="2326a4ca21cedbea61532a5c5b9fcba752f6de2ba9ff9cee5ecb8abda3a6bb98")
  print("Legacy manifest support, malformed rejection and compiled-in identity checks passed")
 }
}
