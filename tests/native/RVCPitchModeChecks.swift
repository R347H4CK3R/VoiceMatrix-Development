import Foundation
@main struct Checks {
 static func main() throws {
  let input=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
  let refined=CommandLine.arguments[3]=="refined"
  let prepared=try RVCFilePreprocessor.prepare(input:input,directory:out)
  let reader=try RVCFloatReader(prepared.url,samples:prepared.samples)
  let plan=try RVCChunkPlan(inputSamples:prepared.samples)
  var pitch=[[Double]]()
  for i in 0..<plan.count {
   pitch.append(try RVCNativePitch.experimentalAutocorrelation(reader.window(plan:plan,index:i),refinePeaks:refined))
  }
  try JSONEncoder().encode(pitch).write(to:out.appendingPathComponent("pitch.json"))
 }
}
