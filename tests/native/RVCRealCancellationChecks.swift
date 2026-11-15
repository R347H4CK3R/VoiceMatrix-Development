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
 struct Result:Codable,Sendable {let phase:String;let cancelled:Bool;let returnedBank:Bool;let blocks:Int;let cacheEmpty:Bool;let descriptorsReleased:Bool}
 static func snapshots()->Int {
  let files=(try? FileManager.default.contentsOfDirectory(atPath:"/proc/self/fd")) ?? []
  return files.filter{((try? FileManager.default.destinationOfSymbolicLink(atPath:"/proc/self/fd/"+$0)) ?? "").contains("/rvc-vectors-")}.count
 }
 static func main() async throws {
  let source=URL(fileURLWithPath:CommandLine.arguments[1]),cache=URL(fileURLWithPath:CommandLine.arguments[2])
  let count=Int(CommandLine.arguments[3])!,digest=CommandLine.arguments[4]
  var results:[Result]=[]
  for phase in ["middle","afterDigest"] {
   let result=try await Task.detached { () throws -> Result in
    let before=snapshots();var blocks=0;var cancelled=false;var returned=false
    let hash=try SHA()
    do {
     let bank=try RVCDiskVectorBank.snapshot(source:source,cache:cache,count:count,expectedSHA256:digest,update:{data in
      blocks+=1;try hash.update(data)
      if phase=="middle" && blocks==3 {withUnsafeCurrentTask{$0?.cancel()}}
     },finish:{
      let value=try hash.finish()
      if phase=="afterDigest" {withUnsafeCurrentTask{$0?.cancel()}}
      return value
     })
     withExtendedLifetime(bank){returned=true}
    } catch is CancellationError {cancelled=true}
    let empty=try FileManager.default.contentsOfDirectory(atPath:cache.path).isEmpty
    return Result(phase:phase,cancelled:cancelled,returnedBank:returned,blocks:blocks,cacheEmpty:empty,descriptorsReleased:snapshots()==before)
   }.value
   results.append(result)
  }
  let data=try JSONEncoder().encode(results)
  try FileHandle.standardOutput.write(contentsOf:data+Data([10]))
  enum Failure:Error {case ignoredCancellation}
  guard results.allSatisfy({$0.cancelled && !$0.returnedBank && $0.cacheEmpty && $0.descriptorsReleased}) else {exit(1)}
 }
}
