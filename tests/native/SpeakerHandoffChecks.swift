import Foundation
@main enum Checks {
 static func main() {
  let hash=String(repeating:"a",count:64), other=String(repeating:"b",count:64)
  let a=LocalSpeakerHandoff.Identity(id:"speaker-a",referenceSHA256:hash)
  let b=LocalSpeakerHandoff.Identity(id:"speaker-b",referenceSHA256:other)
  func select(_ id:String,_ h:String,_ p:[LocalSpeakerHandoff.Identity])->String? { LocalSpeakerHandoff.voiceID(expected:id,referenceSHA256:h,profiles:p) }
  precondition(select("speaker-a",hash,[b,a])=="speaker-a")
  precondition(select("speaker-b",other,[a,b])=="speaker-b")
  precondition(select("speaker-a",other,[a,b])==nil)
  precondition(select("missing",hash,[a,b])==nil)
  precondition(select("speaker-a",hash,[a,a])==nil)
  precondition(select("speaker-a",hash,[a,.init(id:"speaker-a",referenceSHA256:other)])==nil)
  precondition(select("speaker-a","bad",[.init(id:"speaker-a",referenceSHA256:"bad")])==nil)
  precondition(select("",hash,[.init(id:"",referenceSHA256:hash)])==nil)
  precondition(select("speaker-a",hash.uppercased(),[.init(id:"speaker-a",referenceSHA256:hash.uppercased())])==nil)
  print("Exact speaker identity checks passed")
 }
}
