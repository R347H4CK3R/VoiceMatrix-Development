import Foundation
import CryptoKit
@main struct Checks {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let wave=try Data(contentsOf:root.appendingPathComponent("input.wav"))
  func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
  let store=CharacterFolderStore(root:root.appendingPathComponent("library"))
  let originalFolder=root.appendingPathComponent("original")
  let original=try LocalVoiceProfilePackage.write(wave:wave,name:"Existing voice",transcript:"Original words",permissionConfirmed:true,directory:originalFolder,digest:hash)
  _=try await store.importCollection(at:originalFolder)
  var nextWave=wave;nextWave[100] ^= 1
  let newFolder=root.appendingPathComponent("new")
  let new=try LocalVoiceProfilePackage.write(wave:nextWave,name:"New voice",transcript:"New words",permissionConfirmed:true,directory:newFolder,digest:hash)
  let saved=try await store.importCollection(at:newFolder)
  precondition(saved.count==2 && saved.contains{$0.id==new.id})
  let oldURL=try await store.referenceURL(id:original.id)
  let oldData=try Data(contentsOf:oldURL);precondition(oldData==wave)
  let index=root.appendingPathComponent("library/index.json")
  let before=try Data(contentsOf:index)
  let duplicateFolder=root.appendingPathComponent("duplicate")
  _=try LocalVoiceProfilePackage.write(wave:nextWave,name:"Duplicate",transcript:"New words",permissionConfirmed:true,directory:duplicateFolder,digest:hash)
  do {_=try await store.importCollection(at:duplicateFolder);fatalError("duplicate reference admitted")} catch {}
  var unchanged=try Data(contentsOf:index);precondition(unchanged==before)
  let broken=newFolder.appendingPathComponent(new.id+"/reference.wav")
  try wave.write(to:broken)
  do {_=try await store.importCollection(at:newFolder);fatalError("tampered profile admitted")} catch {}
  unchanged=try Data(contentsOf:index);precondition(unchanged==before)
  let cancelled=Task {
   withUnsafeCurrentTask{$0?.cancel()}
   do {_=try await store.importCollection(at:originalFolder);fatalError("cancelled import committed")}
   catch is CancellationError {} catch {fatalError("wrong cancellation")}
  }
  await cancelled.value
  unchanged=try Data(contentsOf:index);precondition(unchanged==before)
  let final=try await store.profiles();precondition(final.count==2)
  print("Direct profiles imported through actual library; prior voice, duplicate, tamper and cancellation checks passed")
 }
}
