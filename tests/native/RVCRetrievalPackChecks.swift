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
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),cache=URL(fileURLWithPath:CommandLine.arguments[2])
  let descriptor=try RVCRetrievalAssets.descriptor(at:root)
  precondition(descriptor.profile=="vctk-p226-ivf1161")
  let hash=try SHA()
  if CommandLine.arguments.last=="reject" {
   do {
    _=try RVCRetrievalAssets.loadCandidate(at:root,cache:cache,digest:SHA.digest,update:hash.update,finish:hash.finish)
    fatalError("Tampered pack accepted")
   } catch {
    let entries=try FileManager.default.contentsOfDirectory(atPath:cache.path);precondition(entries.isEmpty)
    print("Tampered pack rejected without snapshot leak");return
   }
  }
  func snapshots()->Int {
   let files=(try? FileManager.default.contentsOfDirectory(atPath:"/proc/self/fd")) ?? []
   return files.filter{((try? FileManager.default.destinationOfSymbolicLink(atPath:"/proc/self/fd/"+$0)) ?? "").contains("/rvc-vectors-")}.count
  }
  let before=snapshots()
  var index:RVCNativeRetrieval?=try RVCRetrievalAssets.loadCandidate(at:root,cache:cache,digest:SHA.digest,update:hash.update,finish:hash.finish)
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))) as! [String:Any]
  precondition(snapshots()==before+1)
  let found=try index!.search((fixture["features"] as! [Double]).map(Float.init))
  precondition(found.ids==(fixture["expectedIDs"] as! [[Int]]).flatMap{$0})
  let entries=try FileManager.default.contentsOfDirectory(atPath:cache.path);precondition(entries.isEmpty)
  index=nil
  precondition(snapshots()==before,"Snapshot descriptor retained after close")
  print("Pinned pack loading, full-index retrieval and descriptor release passed")
 }
}
