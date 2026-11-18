import Foundation
@main struct Probe {
 static func main() throws {
  let args = CommandLine.arguments
  let url = URL(fileURLWithPath: args[1])
  let table = try MP4SampleTable(url: url)
  if args.count > 2 && args[2] == "mutation" {
   let handle = try FileHandle(forWritingTo:url); try handle.seek(toOffset:0); try handle.write(contentsOf:Data([0])); try handle.close()
   try table.verifyUnchanged(); fatalError("mutation admitted")
  }
  var tracks: [[String:Any]] = []
  for t in [table.video, table.audio] {
   var packets: [[String:Any]] = []
   for s in t.samples { let data = try table.read(s); precondition(data.count == s.size); packets.append(["offset":s.offset,"size":s.size,"pts":s.timestamp,"duration":s.duration,"key":s.key]) }
   tracks.append(["width":t.width,"height":t.height,"rate":t.sampleRate,"channels":t.channels,"packets":packets])
  }
  try table.verifyUnchanged()
  print(String(data:try JSONSerialization.data(withJSONObject:tracks),encoding:.utf8)!)
 }
}
