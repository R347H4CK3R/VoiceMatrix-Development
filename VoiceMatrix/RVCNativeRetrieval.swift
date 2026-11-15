import Foundation

/// IVF-flat L2 search; sparse clusters fall back to bounded exact search.
struct RVCNativeRetrieval {
    enum Failure: Error { case shape, value, missingNeighbors }
    struct Found { let ids: [Int]; let distances: [Float]; let vectors: [Float] }
    /// Keep only the eight best candidates, ordered by distance then original ID.
    /// No candidate-bank-sized distance or fallback-ID array is allocated.
    struct NearestEight {
        private(set) var items:[(id:Int,distance:Double)]=[]
        init() {items.reserveCapacity(8)}
        mutating func consider(id:Int,distance:Double) {
            let position=items.firstIndex {
                distance < $0.distance || (distance == $0.distance && id < $0.id)
            } ?? items.count
            guard position < 8 else {return}
            if items.count == 8 {items.removeLast()}
            items.insert((id,distance),at:position)
        }
    }
    let centroids: [Float]
    let vectors: [Float]
    let lists: [[Int]]
    init(centroids: [Float], vectors: [Float], lists: [[Int]]) throws {
        guard (1...1024).contains(lists.count), centroids.count == lists.count * 768,
              vectors.count % 768 == 0, (8...20000).contains(vectors.count / 768),
              lists.reduce(0, { $0 + $1.count }) == vectors.count / 768 else { throw Failure.shape }
        guard lists.flatMap({$0}).sorted() == Array(0..<(vectors.count / 768)),
              centroids.allSatisfy({$0.isFinite}), vectors.allSatisfy({$0.isFinite}) else { throw Failure.value }
        self.centroids=centroids;self.vectors=vectors;self.lists=lists
    }
    func search(_ features: [Float]) throws -> Found {
        guard features.count % 768 == 0, (1...461).contains(features.count / 768),
              features.allSatisfy({$0.isFinite}) else { throw Failure.shape }
        var ids:[Int]=[];var distances:[Float]=[];var found:[Float]=[]
        func distance(_ row: Int, _ table: [Float], _ id: Int) -> Double {
            var total:Double=0
            for d in 0..<768 { let delta=Double(features[row*768+d])-Double(table[id*768+d]);total += delta*delta }
            return total
        }
        for row in 0..<(features.count/768) {
            try Task.checkCancellation()
            var cluster=0;var best=Double.infinity
            for id in lists.indices {
                let d=distance(row,centroids,id)
                if d < best {best=d;cluster=id}
            }
            // Keep ordinary nprobe=1 behavior. A sparse cluster cannot supply eight
            // genuine neighbors, so search existing vectors without duplicating IDs.
            var nearest=NearestEight()
            func visit(_ id:Int,_ offset:Int) throws {
                if offset % 64 == 0 {try Task.checkCancellation()}
                nearest.consider(id:id,distance:distance(row,vectors,id))
            }
            if lists[cluster].count >= 8 {
                for (offset,id) in lists[cluster].enumerated() {try visit(id,offset)}
            } else {
                for id in 0..<(vectors.count/768) {try visit(id,id)}
            }
            for (id,d) in nearest.items {
                let value=Float(d)
                guard value.isFinite && value > 0 else {throw Failure.value}
                ids.append(id);distances.append(value)
                found.append(contentsOf:vectors[(id*768)..<((id+1)*768)])
            }
        }
        return Found(ids:ids,distances:distances,vectors:found)
    }
}

#if os(iOS)
import CryptoKit
extension RVCNativeRetrieval {
    static func loadVerifiedDiagnosticPack(at root:URL) throws -> RVCNativeRetrieval {
        func read(_ name:String, bytes:Int, sha256:String) throws -> Data {
            let url=root.appendingPathComponent(name)
            guard try RVCSynthesisAssets.regularFile(url) == bytes else {throw RVCSynthesisFailure.invalidAsset}
            let handle=try FileHandle(forReadingFrom:url)
            defer {try? handle.close()}
            let data=try handle.read(upToCount:bytes+1) ?? Data()
            guard data.count == bytes else {throw RVCSynthesisFailure.invalidAsset}
            let hash=SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
            guard hash == sha256 else {throw RVCSynthesisFailure.invalidAsset}
            return data
        }
        func floats(_ data:Data) -> [Float] {
            data.withUnsafeBytes {raw in (0..<(data.count/4)).map{raw.loadUnaligned(fromByteOffset:$0*4,as:Float.self)}}
        }
        let centers=try read("centroids.f32",bytes:457728,sha256:"844e160c8a271bc60c910d9e733dbad0e16183904c400d9e97f40e3a95b3954b")
        let vectors=try read("vectors.f32",bytes:17875968,sha256:"3a438c505e5b82c683b307ff46897d8d869cacf84ad9d1a8d23119a824041370")
        let lists=try read("lists.json",bytes:28284,sha256:"7f735e2b99401c54cdaa41586ca1ae6f3f507f304388674fdcf0c7ffabee5fd4")
        return try RVCNativeRetrieval(centroids:floats(centers),vectors:floats(vectors),
            lists:JSONDecoder().decode([[Int]].self,from:lists))
    }
}
#endif
