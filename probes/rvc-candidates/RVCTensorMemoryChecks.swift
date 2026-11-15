import Foundation
@main struct Probe {
 static func main() throws {
  let direct=CommandLine.arguments[1] == "direct"
  let input=RVCSynthesisInputs(phone:[Float](repeating:0.25,count:922*768),pitch:[Int64](repeating:127,count:922),pitchHz:[Float](repeating:120,count:922),latentNoise:[Float](repeating:0.125,count:922*192),phaseNoise:0.5,excitationNoise:[Float](repeating:-0.25,count:368800))
  var buffers:[String:NSMutableData]=[:]
  var payload=0
  if direct {
   try input.withTensorBytes {name,bytes,_,_ in
    buffers[name]=NSMutableData(bytes:bytes.baseAddress!,length:bytes.count);payload+=bytes.count
   }
  } else {
   let tensors=try input.tensors()
   for (name,tensor) in tensors {buffers[name]=NSMutableData(data:tensor.bytes);payload+=tensor.bytes.count}
   withExtendedLifetime(tensors) {print("legacy intermediate tensor payload: \(payload)")}
  }
  precondition(buffers.count==8)
  precondition(buffers["phone"]!.bytes.loadUnaligned(as:Float.self)==0.25)
  precondition(buffers["excitation_noise"]!.bytes.loadUnaligned(as:Float.self) == -0.25)
  print("owned runtime payload: \(payload)")
 }
}
