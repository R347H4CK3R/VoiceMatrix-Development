import Foundation
final class SHA {
 let task=Process(),input=Pipe(),output=Pipe()
 init() throws {
  task.executableURL=URL(fileURLWithPath:"/usr/bin/sha256sum");task.arguments=["-"];task.standardInput=input;task.standardOutput=output;try task.run()
 }
 deinit {try? input.fileHandleForWriting.close();task.waitUntilExit()}
 func update(_ data:Data) throws {try input.fileHandleForWriting.write(contentsOf:data)}
 func finish() throws -> String {
  try input.fileHandleForWriting.close()
  let data=output.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
  precondition(task.terminationStatus==0);return String(String(data:data,encoding:.utf8)!.prefix(64))
 }
 static func digest(_ data:Data) throws -> String {let hash=try SHA();try hash.update(data);return try hash.finish()}
}
@main struct Checks {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),pack=URL(fileURLWithPath:CommandLine.arguments[2]),cache=URL(fileURLWithPath:CommandLine.arguments[3])
  let out=root.appendingPathComponent("native",isDirectory:true)
  try FileManager.default.createDirectory(at:out,withIntermediateDirectories:false)
  func floats(_ name:String,_ count:Int) throws -> [Float] {
   let data=try Data(contentsOf:root.appendingPathComponent(name))
   precondition(data.count==count*4)
   return data.withUnsafeBytes{raw in (0..<count).map{raw.loadUnaligned(fromByteOffset:$0*4,as:Float.self)}}
  }
  let features=try floats("features.f32",461*768)
  let pitch=try JSONDecoder().decode([[Double]].self,from:Data(contentsOf:root.appendingPathComponent("pitch.json")))[0]
  let noise=try RVCNativePreparation.Noise(latent:floats("latent.f32",192*922),phase:floats("phase.f32",1)[0],excitation:floats("excitation.f32",368800))
  let loadStart=ProcessInfo.processInfo.systemUptime
  let hash=try SHA()
  var index:RVCNativeRetrieval?=try RVCRetrievalAssets.loadCandidate(at:pack,cache:cache,digest:SHA.digest,update:hash.update,finish:hash.finish)
  let loadSeconds=ProcessInfo.processInfo.systemUptime-loadStart
  let started=ProcessInfo.processInfo.systemUptime
  let prepared=try RVCNativePreparation.prepare(features:features,rawPitch:pitch,index:index,noise:noise,indexRate:0.125)
  let prepareSeconds=ProcessInfo.processInfo.systemUptime-started
  try prepared.phone.withUnsafeBytes{try Data($0).write(to:out.appendingPathComponent("phone.f32"))}
  try prepared.pitchHz.withUnsafeBytes{try Data($0).write(to:out.appendingPathComponent("pitchf.f32"))}
  try prepared.pitch.withUnsafeBytes{try Data($0).write(to:out.appendingPathComponent("pitch.i64"))}
  let found=try index!.search(features)
  let report:[String:Any]=["loadSeconds":loadSeconds,"prepareSeconds":prepareSeconds,"rows":461,"neighborIDs":found.ids,"neighborDistances":found.distances,"frames":922]
  try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]).write(to:out.appendingPathComponent("result.json"))
  index=nil
  print("Full real window prepared with verified disk-backed retrieval")
 }
}
