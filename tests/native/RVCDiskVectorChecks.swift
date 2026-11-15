import Foundation
@main struct Checks {
 static func main() throws {
  let source=URL(fileURLWithPath:CommandLine.arguments[1]),cache=URL(fileURLWithPath:CommandLine.arguments[2])
  let count=Int(CommandLine.arguments[3])!,digest=CommandLine.arguments[4]
  let hash=Process(),input=Pipe(),output=Pipe()
  #if os(macOS)
  hash.executableURL=URL(fileURLWithPath:"/usr/bin/shasum");hash.arguments=["-a","256","-"]
  #else
  hash.executableURL=URL(fileURLWithPath:"/usr/bin/sha256sum");hash.arguments=["-"]
  #endif
  hash.standardInput=input;hash.standardOutput=output;try hash.run()
  let bank=try RVCDiskVectorBank.snapshot(source:source,cache:cache,count:count,expectedSHA256:digest,update:{data in
   try input.fileHandleForWriting.write(contentsOf:data)
  },finish:{
   try input.fileHandleForWriting.close()
   let text=String(data:output.fileHandleForReading.readDataToEndOfFile(),encoding:.utf8)!
   hash.waitUntilExit();precondition(hash.terminationStatus==0)
   return String(text.prefix(64))
  })
  let samples=[0,15,16,count/2,count-1].filter{(0..<count).contains($0)}
  let original=try FileHandle(forReadingFrom:source);defer {try? original.close()}
  for id in samples {
   try original.seek(toOffset:UInt64(id*768*4))
   let data=try original.read(upToCount:768*4)!
   let want=data.withUnsafeBytes{raw in (0..<768).map{Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}}
   let actual=try bank.row(id);precondition(actual==want)
  }
  do {_=try bank.row(-1);fatalError("negative row accepted")} catch {}
  do {_=try bank.row(count);fatalError("end row accepted")} catch {}
  let remaining=try FileManager.default.contentsOfDirectory(atPath:cache.path);precondition(remaining.isEmpty,"Snapshot path leaked")
  // Mutating the caller-owned input must not change the verified snapshot.
  let saved=try bank.row(0)
  _=try bank.row(count-1)
  let writer=try FileHandle(forWritingTo:source);try writer.truncate(atOffset:0);try writer.close()
  let isolated=try bank.row(0);precondition(isolated==saved)
  if CommandLine.arguments.count>5 {
   let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[5]))
   let x=try JSONSerialization.jsonObject(with:data) as! [String:Any]
   let index=try RVCNativeRetrieval(centroids:(x["centroids"] as! [Double]).map(Float.init),bank:bank,lists:x["lists"] as! [[Int]])
   let found=try index.search((x["features"] as! [Double]).map(Float.init))
   precondition(found.ids == (x["expectedIDs"] as! [[Int]]).flatMap{$0})
   let expected=(x["expectedDistances"] as! [[Double]]).flatMap{$0}
   for (actual,want) in zip(found.distances,expected) {precondition(abs(Double(actual)-want)<0.001)}
   print("Full-index native search matched FAISS IDs and distances")
  }
  if count==8 {
   let index=try RVCNativeRetrieval(centroids:[Float](repeating:0,count:768)+[Float](repeating:1000000,count:768),bank:bank,lists:[[7],Array(0..<7)])
   let found=try index.search([Float](repeating:0,count:768))
   precondition(found.ids == Array(0..<8),"Disk sparse fallback changed ordering")
   do {
    _=try RVCNativeRetrieval(centroids:[Float](repeating:0,count:768),bank:bank,lists:[[0,0,1,2,3,4,5,6]])
    fatalError("duplicate index IDs accepted")
   } catch {}
  }
  print("Verified actual vector rows, block boundaries, bounds and snapshot isolation")
 }
}
