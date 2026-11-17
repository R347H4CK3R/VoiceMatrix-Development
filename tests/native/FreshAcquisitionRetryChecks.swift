import Foundation
@main struct Checks {
 static func main() throws {
  let page=URL(string:"https://www.youtube.com/watch?v=abcdefghijk")!
  let short=URL(string:"https://youtu.be/abcdefghijk")!
  let other=URL(string:"https://youtu.be/zyxwvutsrqp")!
  let direct=URL(string:"https://archive.org/download/example/source.mp4")!
  func check(_ original:URL?,_ retained:URL?,_ complete:Bool=false,_ source:Bool=false)->URL? {
   LocalMediaURLPolicy.freshAcquisitionInput(original:original,retained:retained,completed:complete,hasSource:source)
  }
  precondition(check(short,page)==page)
  precondition(check(nil,page)==page) // Legacy receipt keeps canonical original.
  precondition(check(direct,direct)==direct)
  precondition(check(other,page)==nil)
  precondition(check(short,nil)==nil)
  precondition(check(short,page,true)==nil)
  precondition(check(short,page,false,true)==nil)
  precondition(check(URL(fileURLWithPath:"/tmp/private.mp4"),page)==nil)
  precondition(check(URL(string:"https://r1.googlevideo.com/videoplayback?secret=x")!,page)==nil)
  precondition(check(nil,URL(string:"https://127.0.0.1/private")!)==nil)
  precondition(check(nil,URL(string:"https://user:password@archive.org/source.mp4")!)==nil)
  print("Fresh-acquisition source provenance checks passed")
 }
}
