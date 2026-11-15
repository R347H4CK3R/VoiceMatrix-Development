import Foundation
@main struct Checks {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let wave=try Data(contentsOf:root.appendingPathComponent("input.wav"))
  let digest=CommandLine.arguments[2]
  let package=root.appendingPathComponent("package")
  let profile=try LocalVoiceProfilePackage.write(wave:wave,name:"  My voice  ",transcript:"The exact spoken words.",permissionConfirmed:true,directory:package,digest:{_ in digest})
  precondition(profile.name=="My voice" && profile.referenceText=="The exact spoken words." && !profile.trainedModel)
  let manifest=try JSONDecoder().decode(LocalVoiceProfilePackage.Profile.self,from:Data(contentsOf:package.appendingPathComponent(profile.id+"/manifest.json")))
  precondition(manifest.referenceSHA256==digest && manifest.engine=="F5TTS_v1_Base")
  let savedWave=try Data(contentsOf:package.appendingPathComponent(profile.id+"/reference.wav"))
  precondition(savedWave == wave)
  let collection=try JSONSerialization.jsonObject(with:Data(contentsOf:package.appendingPathComponent("collection.json"))) as! [String:Any]
  precondition((collection["voices"] as! [[String:String]])[0]["id"]==profile.id)
  for (name,text,permission) in [("", "words",true),("Name","",true),("Name","words",false),(String(repeating:"x",count:81),"words",true),("Name",String(repeating:"x",count:2001),true)] {
   let target=root.appendingPathComponent(UUID().uuidString)
   do {_=try LocalVoiceProfilePackage.write(wave:wave,name:name,transcript:text,permissionConfirmed:permission,directory:target,digest:{_ in digest});fatalError("invalid metadata accepted")} catch {}
   precondition(!FileManager.default.fileExists(atPath:target.path))
  }
  var broken=wave;broken[24]=0
  do {_=try LocalVoiceProfilePackage.write(wave:broken,name:"Name",transcript:"words",permissionConfirmed:true,directory:root.appendingPathComponent("bad"),digest:{_ in digest});fatalError("invalid WAV accepted")} catch {}
  let task=Task {
   let target=root.appendingPathComponent("cancelled")
   do {_=try LocalVoiceProfilePackage.write(wave:wave,name:"Name",transcript:"words",permissionConfirmed:true,directory:target,digest:{_ in withUnsafeCurrentTask{$0?.cancel()};return digest});fatalError("cancelled profile saved")}
   catch is CancellationError {} catch {fatalError("wrong cancellation")}
   precondition(!FileManager.default.fileExists(atPath:target.path))
  }
  await task.value
  do {_=try LocalVoiceProfilePackage.write(wave:wave,name:"Again",transcript:"words",permissionConfirmed:true,directory:package,digest:{_ in digest});fatalError("existing directory overwritten")} catch {}
  precondition(FileManager.default.fileExists(atPath:package.appendingPathComponent("collection.json").path))
  print("Reference package validation, format, cancellation and preservation passed")
 }
}
