// Test-only CryptoKit API bridge for Linux; hashes are real /usr/bin/sha256sum results.
import Foundation
public enum SHA256 {
 public static func hash(data:Data)->[UInt8] {
  let task=Process(),input=Pipe(),output=Pipe()
  task.executableURL=URL(fileURLWithPath:"/usr/bin/sha256sum");task.arguments=["-"]
  task.standardInput=input;task.standardOutput=output
  do {
   try task.run();try input.fileHandleForWriting.write(contentsOf:data);try input.fileHandleForWriting.close()
   let raw=output.fileHandleForReading.readDataToEndOfFile();task.waitUntilExit()
   precondition(task.terminationStatus==0)
   let hex=String(String(data:raw,encoding:.utf8)!.prefix(64))
   return stride(from:0,to:64,by:2).map{offset in
    let start=hex.index(hex.startIndex,offsetBy:offset)
    return UInt8(hex[start..<hex.index(start,offsetBy:2)],radix:16)!
   }
  } catch {fatalError("Test SHA256 process failed")}
 }
}
