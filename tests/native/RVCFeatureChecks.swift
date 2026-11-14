import Foundation
@main struct Checks {
 static func main() async throws {
  let raw=FileHandle.standardInput.readDataToEndOfFile()
  let input=try JSONSerialization.jsonObject(with:raw) as! [String:Any]
  var result:[String:Any]
  do {
   if input["cancel"] as? Bool == true {
    let task=Task { () -> Bool in
     withUnsafeCurrentTask { $0?.cancel() }
     do { _=try RVCFeaturePreparation.pitch([100],semitones:0);return false }
     catch is CancellationError { return true }
    }
    result=["cancelled":try await task.value]
   } else if let pitch=input["pitch"] as? [Double] {
    let output=try RVCFeaturePreparation.pitch(pitch,semitones:input["semitones"] as! Double)
    result=["hz":output.hz,"coarse":output.coarse]
   } else {
    let output=try RVCFeaturePreparation.features(
     (input["features"] as! [Double]).map(Float.init), rows:input["rows"] as! Int,
     neighbors:(input["vectors"] as! [Double]).map(Float.init), distances:(input["distances"] as! [Double]).map(Float.init),
     indexRate:Float(input["indexRate"] as! Double), protect:Float(input["protect"] as! Double),
     pitchHz:(input["pitchHz"] as! [Double]).map(Float.init))
    result=["features":output.values,"frames":output.frames]
   }
  } catch { result=["error":String(describing:error)] }
  FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]))
 }
}
