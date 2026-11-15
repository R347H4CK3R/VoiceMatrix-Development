import Foundation

/// Profiles select compiled-in file identities; manifests cannot authorize new hashes.
enum RVCRetrievalAssets {
    enum Failure:Error {case invalidPack}
    struct Manifest:Codable {let schemaVersion:Int;let profile:String}
    struct File {let name:String;let bytes:Int;let sha256:String}
    struct Descriptor {let profile:String;let files:[File]}
    static let diagnosticProfile="diagnostic-ivf149"
    static let candidateProfile="vctk-p226-ivf1161"
    static func descriptor(at root:URL) throws -> Descriptor {
        let url=root.appendingPathComponent("manifest.json")
        let profile:String
        if FileManager.default.fileExists(atPath:url.path) {
            guard try RVCSynthesisAssets.regularFile(url)<=4096 else {throw Failure.invalidPack}
            let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()}
            let data=try handle.read(upToCount:4097) ?? Data()
            guard data.count<=4096 else {throw Failure.invalidPack}
            let m=try JSONDecoder().decode(Manifest.self,from:data)
            guard m.schemaVersion==1 else {throw Failure.invalidPack}
            profile=m.profile
        } else {profile=diagnosticProfile}
        switch profile {
        case diagnosticProfile:
            return Descriptor(profile:profile,files:[
                File(name:"centroids.f32",bytes:457728,sha256:"844e160c8a271bc60c910d9e733dbad0e16183904c400d9e97f40e3a95b3954b"),
                File(name:"vectors.f32",bytes:17875968,sha256:"3a438c505e5b82c683b307ff46897d8d869cacf84ad9d1a8d23119a824041370"),
                File(name:"lists.json",bytes:28284,sha256:"7f735e2b99401c54cdaa41586ca1ae6f3f507f304388674fdcf0c7ffabee5fd4")])
        case candidateProfile:
            return Descriptor(profile:profile,files:[
                File(name:"centroids.f32",bytes:3566592,sha256:"36358a8e879e3f7d15222ab4771ad1e168479ee3fc80e7359097b381a0763dd1"),
                File(name:"vectors.f32",bytes:139201536,sha256:"2326a4ca21cedbea61532a5c5b9fcba752f6de2ba9ff9cee5ecb8abda3a6bb98"),
                File(name:"lists.json",bytes:263091,sha256:"68579a69b9cb75d7c84a8a956b6f6879e7c4b8e5d3e1554c0e4b2f72fde357eb")])
        default:throw Failure.invalidPack
        }
    }
    static func loadCandidate(at root:URL,cache:URL,digest:(Data)throws->String,
                              update:(Data)throws->Void,finish:()throws->String) throws -> RVCNativeRetrieval {
        let pack=try descriptor(at:root)
        guard pack.profile==candidateProfile else {throw Failure.invalidPack}
        func read(_ name:String) throws -> Data {
            let file=pack.files.first{$0.name==name}!
            let url=root.appendingPathComponent(name)
            guard try RVCSynthesisAssets.regularFile(url)==file.bytes else {throw Failure.invalidPack}
            let handle=try FileHandle(forReadingFrom:url);defer {try? handle.close()}
            let data=try handle.read(upToCount:file.bytes+1) ?? Data()
            guard data.count==file.bytes,try digest(data)==file.sha256 else {throw Failure.invalidPack}
            return data
        }
        let centers=try read("centroids.f32"),listData=try read("lists.json")
        let centroids=centers.withUnsafeBytes {raw in
            (0..<(centers.count/4)).map {Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))}
        }
        let lists=try JSONDecoder().decode([[Int]].self,from:listData)
        guard lists.count==1161 else {throw Failure.invalidPack}
        let vectors=pack.files.first{$0.name=="vectors.f32"}!
        let bank=try RVCDiskVectorBank.snapshot(source:root.appendingPathComponent(vectors.name),
            cache:cache,count:45313,expectedSHA256:vectors.sha256,update:update,finish:finish)
        return try RVCNativeRetrieval(centroids:centroids,bank:bank,lists:lists)
    }
}
#if os(iOS)
import CryptoKit
extension RVCNativeRetrieval {
    static func loadVerifiedPack(at root:URL,cache:URL,expectedProfile:String) throws -> RVCNativeRetrieval {
        let pack=try RVCRetrievalAssets.descriptor(at:root)
        guard pack.profile==expectedProfile else {throw RVCRetrievalAssets.Failure.invalidPack}
        if pack.profile==RVCRetrievalAssets.diagnosticProfile {return try loadVerifiedDiagnosticPack(at:root)}
        var hasher=SHA256()
        return try RVCRetrievalAssets.loadCandidate(at:root,cache:cache,
            digest:{SHA256.hash(data:$0).map{String(format:"%02x",$0)}.joined()},
            update:{hasher.update(data:$0)},
            finish:{hasher.finalize().map{String(format:"%02x",$0)}.joined()})
    }
}
#endif
