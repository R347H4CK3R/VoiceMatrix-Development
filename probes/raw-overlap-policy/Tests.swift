import Foundation
@main struct Tests {
 static func main() async throws {
  func check(_ value:Bool) {precondition(value)}
  let sha=String(repeating:"a",count:64),revision="test-revision"
  func make(_ weights:[[[Float]]],_ offsets:[Double]=[0],duration:Double=4) throws -> LocalOverlapPolicy.Evidence {
   try LocalOverlapPolicy.build(weights:weights,offsets:offsets,frameDuration:1,duration:duration,sourceSHA256:sha,modelRevision:revision)
  }
  let e=try make([[[1,0],[1,1],[1,1],[1,0]]])
  check(e.counts==[1,2,2,1])
  check(try LocalOverlapPolicy.allows(start:0,end:1,evidence:e))
  check(!(try LocalOverlapPolicy.allows(start:0.5,end:1.1,evidence:e)))
  check(try LocalOverlapPolicy.allows(start:3,end:4,evidence:e))
  let unknown=try make([[[1,0],[1,0]]])
  check(unknown.counts==[1,1,-1,-1])
  check(!(try LocalOverlapPolicy.allows(start:1.5,end:3,evidence:unknown)))
  let merged=try make([[[1,1],[1,1]],[[1,0],[1,0]]],[0,1],duration:3)
  check(merged.counts==[2,2,1]) // 1.5 rounds nearest-even, unchanged model rule.
  let eof=try make([[[1,0],[1,0],[1,1],[1,1]]],duration:2)
  check(eof.counts==[1,1]) // Padded model frames cannot contaminate final source frame.
  for duration in [0,Double.nan,1801] {
   do { _=try make([[[1,0]]],duration:duration);fatalError("Bad duration accepted") }catch{}
  }
  let invalidWeights: [[[[Float]]]] = [[],[[[Float.nan,0]]],[[[1.1,0]]],[[[]]]]
  for weights in invalidWeights {
   do {_=try make(weights);fatalError("Invalid weights accepted")}catch{}
  }
  var bad=e;bad.counts=[1]
  do {try LocalOverlapPolicy.validate(bad);fatalError("Truncated evidence accepted")}catch{}
  for (a,b) in [(-1.0,1.0),(1,1),(0,5)] {
   do {_=try LocalOverlapPolicy.allows(start:a,end:b,evidence:e);fatalError("Bad crop accepted")}catch{}
  }
  let fractional=try LocalOverlapPolicy.build(weights:[[[1,0],[1,0],[1,0]],[[1,1],[1,1],[1,1]]],offsets:[0,0.1875],frameDuration:0.125,duration:1,sourceSHA256:sha,modelRevision:revision)
  check(fractional.counts==[1,1,2,2,2,-1,-1,-1])
  let ties=try make([[[0.5,0,0],[1,0.5,0],[1,1,0.5],[1,1,1]]])
  check(ties.counts==[0,2,2,3])
  let short=try make([[[1,0],[1,1]]],duration:1.5)
  check(try LocalOverlapPolicy.allows(start:0,end:1,evidence:short))
  check(!(try LocalOverlapPolicy.allows(start:1,end:1.5,evidence:short)))
  for offsets in [[0.0,0.0],[1.0,0.0],[-0.1,1],[0,Double.nan],[]] {
   do {_=try make([[[1,0]],[[1,0]]],offsets);fatalError("Invalid offsets accepted")}catch{}
  }
  let raggedRows:[[[[Float]]]] = [[[[1,0],[1]]],[[[1,0]],[]]]
  for ragged in raggedRows {
   do {_=try make(ragged,Array(repeating:0,count:ragged.count));fatalError("Invalid shape accepted")}catch{}
  }
  func badEvidence(_ version:Int=1,_ hash:String=String(repeating:"a",count:64),_ model:String="test",_ counts:[Int]=[1,2,2,1]) -> LocalOverlapPolicy.Evidence {
   .init(version:version,sourceSHA256:hash,modelRevision:model,duration:4,frameDuration:1,speakerSlots:2,counts:counts)
  }
  for invalid in [badEvidence(2),badEvidence(1,"abc"),badEvidence(1,sha,""),badEvidence(1,sha,"x",[1,3,1,1]),badEvidence(1,sha,"x",[1,-2,1,1])] {
   do {try LocalOverlapPolicy.validate(invalid);fatalError("Malformed stored evidence accepted")}catch{}
  }
  do {_=try LocalOverlapPolicy.build(weights:[[[1,0]]],offsets:[0],frameDuration:0.001,duration:1800,sourceSHA256:sha,modelRevision:revision);fatalError("Resource bound accepted")}catch{}
  let cancelled=Task {try Task.checkCancellation();return try make([[[1,0],[1,0],[1,0],[1,0]]])}
  cancelled.cancel()
  do {_=try await cancelled.value;fatalError("Cancellation ignored")}catch is CancellationError {}
  print("PASS raw overlap counts, boundaries, unknown coverage, exact aggregation, EOF and invalid evidence")
 }
}
