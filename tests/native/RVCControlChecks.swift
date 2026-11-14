import Foundation
@main struct Checks {
 static func main() throws {
  let x=try JSONSerialization.jsonObject(with:FileHandle.standardInput.readDataToEndOfFile()) as! [String:Double]
  do {
   let index = x["noIndex"] == 1 ? nil : try RVCNativeRetrieval(centroids:[Float](repeating:0,count:768), vectors:(1...8).flatMap{[Float](repeating:Float($0),count:768)},lists:[Array(0..<8)])
   let noise=RVCNativePreparation.Noise(latent:[Float](repeating:0,count:922*192),phase:0.5,excitation:[Float](repeating:0,count:368800))
   let result=try RVCNativePreparation.prepare(features:[Float](repeating:0.25,count:461*768),rawPitch:[Double](repeating:100,count:923),index:index,noise:noise,semitones:x["shift"] ?? 0,indexRate:Float(x["rate"] ?? 0.75))
   print(String(data:try JSONSerialization.data(withJSONObject:["first":result.phone[0],"last":result.phone.last!,"pitch":result.pitchHz[0],"count":result.phone.count]),encoding:.utf8)!)
  } catch {print("{\"rejected\":true}")}
 }
}
