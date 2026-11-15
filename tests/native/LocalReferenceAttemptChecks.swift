import Foundation
@main struct Checks {
 static func main() async throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  var attempt=try LocalReferenceAttempt(sourceSHA256:String(repeating:"a",count:64),speaker:"speaker_1",start:1,end:7)
  try attempt.record(.selected,reason:"Window selected",directory:root)
  try attempt.record(.extracted,reason:"Reference extracted",referenceSHA256:String(repeating:"b",count:64),directory:root)
  do {try attempt.record(.referenceNoSpeech,reason:"Changed clip",referenceSHA256:String(repeating:"c",count:64),directory:root);fatalError("reference drift accepted")} catch {}
  precondition(attempt.events.count==2)
  try attempt.record(.referenceNoSpeech,reason:"No speech recognized",referenceSHA256:String(repeating:"b",count:64),directory:root)
  let data=try Data(contentsOf:root.appendingPathComponent("candidate-"+attempt.id+".json"))
  let restored=try JSONDecoder().decode(LocalReferenceAttempt.self,from:data)
  precondition(restored.events.count==3 && restored.sourceSHA256==String(repeating:"a",count:64))
  do {try attempt.record(.selected,reason:"Overwrite terminal result",directory:root);fatalError("terminal history changed")} catch {}
  let after=try Data(contentsOf:root.appendingPathComponent("candidate-"+attempt.id+".json"));precondition(after==data)
  do {_=try LocalReferenceAttempt(sourceSHA256:"bad",speaker:"s",start:0,end:4);fatalError("bad hash")} catch {}
  do {_=try LocalReferenceAttempt(sourceSHA256:String(repeating:"a",count:64),speaker:"../escape",start:0,end:4);fatalError("unsafe speaker")} catch {}
  var saved=try LocalReferenceAttempt(sourceSHA256:String(repeating:"a",count:64),speaker:"s",start:0,end:4)
  do {try saved.record(.saved,reason:"Saved",directory:root);fatalError("unbound saved claim")} catch {}
  try saved.record(.saved,reason:"Saved reference; likeness unverified",referenceSHA256:String(repeating:"b",count:64),previewSHA256:String(repeating:"c",count:64),voiceID:"local-example",directory:root)
  precondition(saved.events.count==1)
  var active=try LocalReferenceAttempt(sourceSHA256:String(repeating:"a",count:64),speaker:"paused",start:0,end:4)
  try active.record(.selected,reason:"Selected before pause",directory:root)
  let activeURL=root.appendingPathComponent("candidate-"+active.id+".json")
  let beforePause=try Data(contentsOf:activeURL)
  let copy=active
  let task=Task {
   var cancelled=copy
   withUnsafeCurrentTask{$0?.cancel()}
   do {try cancelled.record(.extracted,reason:"Must not commit",referenceSHA256:String(repeating:"b",count:64),directory:root);fatalError("cancelled event written")}
   catch is CancellationError {} catch {fatalError("wrong cancellation")}
  }
  await task.value
  let afterPause=try Data(contentsOf:activeURL);precondition(afterPause==beforePause)
  print("Candidate provenance, terminal outcomes and saved-asset bindings passed")
 }
}
