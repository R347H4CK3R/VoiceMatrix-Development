import Foundation
@main struct Check {
 static func main() throws {
  let input=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
  let index=try RVCNativeRetrieval(centroids:(input["centroids"] as! [Double]).map(Float.init),vectors:(input["vectors"] as! [Double]).map(Float.init),lists:input["lists"] as! [[Int]])
  let result=try index.search((input["features"] as! [Double]).map(Float.init))
  precondition(result.ids == (input["expectedIDs"] as! [[Int]]).flatMap{$0})
  let data=try JSONSerialization.data(withJSONObject:["ids":result.ids,"distances":result.distances,"vectors":result.vectors],options:[.sortedKeys])
  try data.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
 }
}
