import Foundation
@main struct Replay {
 struct Case: Codable {let id:String;let analysis:LocalSpeakerDiarization.Analysis;let evidence:LocalOverlapPolicy.Evidence}
 struct Result: Codable {let id:String;let candidates:Int;let retained:Int;let excluded:Int}
 static func main() throws {
  let cases=try JSONDecoder().decode([Case].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
  precondition(cases.count==5)
  precondition(Set(cases.map(\.id))==Set(["sequential","partial-2s","full-equal","full-quieter","single-A"]))
  var results:[Result]=[]
  for item in cases {
   let legacy=try LocalSpeakerDiarization.validatedForCurrentPolicy(item.analysis)
   try LocalOverlapPolicy.validate(item.evidence)
   precondition(item.evidence.duration==legacy.seconds && item.evidence.modelRevision==legacy.modelRevision)
   let filtered=try LocalSpeakerDiarization.excludingRawOverlap(legacy.speakerWindows,evidence:item.evidence)
   let before=legacy.speakerWindows.reduce(0){$0+$1.windows.count},after=filtered.reduce(0){$0+$1.windows.count}
   if item.id=="single-A" || item.id=="sequential" {precondition(before==after,"Clean control changed")}
   if item.id=="full-equal" || item.id=="full-quieter" {precondition(after<before,"Expected observed overlap not vetoed")}
   let current=LocalSpeakerDiarization.Analysis(modelRevision:legacy.modelRevision,seconds:legacy.seconds,segments:legacy.segments,speakerWindows:filtered,selectionPolicyVersion:5,rawOverlap:item.evidence)
   _=try LocalSpeakerDiarization.validatedForCurrentPolicy(current)
   results.append(Result(id:item.id,candidates:before,retained:after,excluded:before-after))
  }
  print(String(decoding:try JSONEncoder().encode(results),as:UTF8.self))
 }
}
