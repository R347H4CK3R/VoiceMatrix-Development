import Foundation
@main struct Checks {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),source=root.appendingPathComponent("input.f32"),cache=root.appendingPathComponent("cache")
  let zeros=String(repeating:"0",count:64),ones=String(repeating:"1",count:64)
  func rejected(_ url:URL,_ count:Int,_ digest:String) throws {
   do {
    _=try RVCDiskVectorBank.snapshot(source:url,cache:cache,count:count,expectedSHA256:digest,update:{_ in},finish:{zeros})
    fatalError("invalid snapshot accepted")
   } catch {}
   let entries=try FileManager.default.contentsOfDirectory(atPath:cache.path)
   precondition(entries.isEmpty,"failed snapshot leaked")
  }
  try rejected(source,8,ones) // mismatched computed hash
  try rejected(source,9,zeros) // truncated vector bank
  try rejected(source,50001,zeros)
  let link=root.appendingPathComponent("link.f32")
  try FileManager.default.createSymbolicLink(at:link,withDestinationURL:source)
  try rejected(link,8,zeros)
  let writer=try FileHandle(forWritingTo:source)
  var bits=Float.nan.bitPattern.littleEndian
  try writer.write(contentsOf:withUnsafeBytes(of:&bits){Data($0)});try writer.close()
  try rejected(source,8,zeros)
  let task=Task {
   withUnsafeCurrentTask{$0?.cancel()}
   do {
    _=try RVCDiskVectorBank.snapshot(source:source,cache:cache,count:8,expectedSHA256:zeros,update:{_ in},finish:{zeros})
    fatalError("cancellation ignored")
   } catch is CancellationError {} catch {fatalError("wrong cancellation error")}
  }
  await task.value
  let entries=try FileManager.default.contentsOfDirectory(atPath:cache.path);precondition(entries.isEmpty)
  print("Hash, length, count, symlink, nonfinite and cancellation rejection passed")
 }
}
