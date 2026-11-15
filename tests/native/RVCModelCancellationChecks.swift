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
 struct Result:Codable,Sendable {let phase:String;let cancelled:Bool;let returnedSnapshot:Bool;let blocks:Int;let cacheEmpty:Bool}
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),cache=URL(fileURLWithPath:CommandLine.arguments[2])
  if CommandLine.arguments.last=="reject" {
   let hash=try SHA()
   var rejected=false
   do {
    let saved=try RVCSynthesisAssets.snapshot(root:root,cache:cache,profile:"hubert-147680-cpu",update:{try! hash.update($0)},finish:{try! hash.finish()})
    try FileManager.default.removeItem(at:saved.deletingLastPathComponent())
   } catch RVCSynthesisFailure.invalidAsset {rejected=true}
   let empty=try FileManager.default.contentsOfDirectory(atPath:cache.path).isEmpty
   let report=["rejected":rejected,"cacheEmpty":empty]
   try FileHandle.standardOutput.write(contentsOf:JSONEncoder().encode(report)+Data([10]))
   guard rejected && empty else {exit(1)}
   return
  }
  var results:[Result]=[]
  for phase in ["middle","afterDigest"] {
   let result=try await Task.detached { () throws -> Result in
    var blocks=0;var cancelled=false;var saved:URL?
    let hash=try SHA()
    do {
     saved=try RVCSynthesisAssets.snapshot(root:root,cache:cache,profile:"hubert-147680-cpu",update:{data in
      blocks+=1;try! hash.update(data)
      if phase=="middle" && blocks==3 {withUnsafeCurrentTask{$0?.cancel()}}
     },finish:{
      let value=try! hash.finish()
      if phase=="afterDigest" {withUnsafeCurrentTask{$0?.cancel()}}
      return value
     })
    } catch is CancellationError {cancelled=true}
    let empty=try FileManager.default.contentsOfDirectory(atPath:cache.path).isEmpty
    if let saved {try FileManager.default.removeItem(at:saved.deletingLastPathComponent())}
    return Result(phase:phase,cancelled:cancelled,returnedSnapshot:saved != nil,blocks:blocks,cacheEmpty:empty)
   }.value
   results.append(result)
  }
  try FileHandle.standardOutput.write(contentsOf:JSONEncoder().encode(results)+Data([10]))
  guard results.allSatisfy({$0.cancelled && !$0.returnedSnapshot && $0.cacheEmpty}) else {exit(1)}
 }
}
