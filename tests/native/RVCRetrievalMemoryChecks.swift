import Foundation
@main struct Checks {
 static func main() throws {
  var nearest=RVCNativeRetrieval.NearestEight()
  // Descending IDs and repeated distances catch incorrect tie replacement.
  let values=(0..<20000).reversed().map{(id:$0,distance:Double(($0*73)%97))}
  for v in values {
   nearest.consider(id:v.id,distance:v.distance)
   precondition(nearest.items.count<=8,"Candidate storage grew beyond eight")
  }
  let expected=values.sorted{$0.distance == $1.distance ? $0.id<$1.id : $0.distance<$1.distance}.prefix(8)
  precondition(nearest.items.map{$0.id} == expected.map{$0.id})
  precondition(nearest.items.map{$0.distance} == expected.map{$0.distance})
  // A sparse closest cluster must search all genuine vectors.
  let vectors=(1...64).flatMap{[Float](repeating:Float($0),count:768)}
  let index=try RVCNativeRetrieval(centroids:[Float](repeating:0,count:768)+[Float](repeating:100,count:768),vectors:vectors,lists:[[63],Array(0..<63)])
  let found=try index.search([Float](repeating:0,count:768))
  precondition(found.ids == Array(0..<8))
  precondition(found.distances == (1...8).map{Float($0*$0*768)})
  precondition(found.vectors == Array(vectors.prefix(8*768)))
  print("Bounded selection, tie ordering and sparse fallback passed")
 }
}
