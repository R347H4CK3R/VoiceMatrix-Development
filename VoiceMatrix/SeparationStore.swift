import Foundation
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Private app-owned storage. Inputs and committed pairs are never automatically removed.
struct SeparationStore {
    enum Failure: Error { case invalid, bounds, unsafe, storage }
    struct Receipt: Codable {
        let id: UUID
        let date: Date
        let inputName: String
        let inputSHA256: String
        let modelSHA256: [String:String]
        let frames: Int
        let gain: Float
        let vocalsSHA256: String
        let accompanimentSHA256: String
    }
    struct Result: Identifiable {
        let receipt: Receipt
        let directory: URL
        var id: UUID { receipt.id }
        var frames: Int { receipt.frames }
        var gain: Float { receipt.gain }
        var vocals: URL { directory.appendingPathComponent("Vocals-"+id.uuidString+".wav") }
        var accompaniment: URL { directory.appendingPathComponent("Accompaniment-"+id.uuidString+".wav") }
    }
    let root: URL
    static var standard: SeparationStore {
        SeparationStore(root:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("VocalSeparation",isDirectory:true))
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        var info=stat()
        guard lstat(root.path,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR) else {throw Failure.unsafe}
    }
    /// A bounded directory count also bounds retained interrupted staging attempts.
    func admit() throws {
        try prepare()
        let children=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
        guard children.count<64 else {throw Failure.bounds}
        let attrs=try FileManager.default.attributesOfFileSystem(forPath:root.path)
        guard let free=attrs[.systemFreeSize] as? NSNumber, free.int64Value>192*1024*1024 else {throw Failure.storage}
    }
    static func digest(_ url:URL,maximum:Int64) throws -> String {
        var hash=SHA256()
        try RetainedMediaReader.read(url,maximumBytes:maximum){ hash.update(data:$0) }
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    func copyInput(_ source:URL) throws -> (url:URL,sha:String) {
        try admit()
        let target=root.appendingPathComponent("Input-"+UUID().uuidString).appendingPathExtension(source.pathExtension.lowercased())
        var complete=false
        defer {if !complete {try? FileManager.default.removeItem(at:target)}}
        try Data().write(to:target,options:.withoutOverwriting)
        let output=try FileHandle(forWritingTo:target);defer{try? output.close()}
        var hash=SHA256()
        try RetainedMediaReader.read(source,maximumBytes:64*1024*1024) {bytes in
            hash.update(data:bytes);try output.write(contentsOf:bytes)
        }
        try output.synchronize();try Task.checkCancellation()
        complete=true
        return (target,hash.finalize().map{String(format:"%02x",$0)}.joined())
    }
    func publish(vocals:[Float],accompaniment:[Float],inputName:String,inputSHA256:String) throws -> Result {
        guard !vocals.isEmpty,vocals.count%2==0,vocals.count<=882000,
              vocals.count==accompaniment.count,vocals.allSatisfy(\.isFinite),accompaniment.allSatisfy(\.isFinite),
              inputSHA256.count==64,inputSHA256.allSatisfy({$0.isHexDigit}) else {throw Failure.invalid}
        try admit();try Task.checkCancellation()
        let id=UUID(), staging=root.appendingPathComponent(".staging-"+UUID().uuidString,isDirectory:true)
        let destination=root.appendingPathComponent("Result-"+id.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var complete=false
        defer{if !complete {try? FileManager.default.removeItem(at:staging)}}
        let peak=max(vocals.reduce(Float(0)){max($0,abs($1))},accompaniment.reduce(Float(0)){max($0,abs($1))})
        let gain:Float=peak>1 ? 1/peak : 1
        let vocal=staging.appendingPathComponent("Vocals-"+id.uuidString+".wav"), backing=staging.appendingPathComponent("Accompaniment-"+id.uuidString+".wav")
        try Self.writeWAV(vocals,gain:gain,to:vocal)
        try Self.writeWAV(accompaniment,gain:gain,to:backing)
        let receipt=Receipt(id:id,date:Date(),inputName:String(inputName.prefix(120)),inputSHA256:inputSHA256,
                            modelSHA256:VocalSeparationAssets.models.mapValues{$0.sha256},frames:vocals.count/2,gain:gain,
                            vocalsSHA256:try Self.digest(vocal,maximum:4_000_000),
                            accompanimentSHA256:try Self.digest(backing,maximum:4_000_000))
        let metadata=staging.appendingPathComponent("receipt.json")
        try JSONEncoder().encode(receipt).write(to:metadata,options:.withoutOverwriting)
        let h=try FileHandle(forWritingTo:metadata);try h.synchronize();try h.close()
        try Task.checkCancellation()
#if canImport(Darwin)
        guard renamex_np(staging.path,destination.path,UInt32(RENAME_EXCL))==0 else {throw Failure.storage}
#else
        throw Failure.unsafe
#endif
        complete=true // Commit wins late cancellation; no throwing work afterward.
        return Result(receipt:receipt,directory:destination)
    }
    static func writeWAV(_ samples:[Float],gain:Float,to url:URL) throws {
        var data=Data()
        func word<T:FixedWidthInteger>(_ x:T) {var value=x.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
        data.append(contentsOf:"RIFF".utf8);word(UInt32(36+samples.count*4));data.append(contentsOf:"WAVEfmt ".utf8)
        word(UInt32(16));word(UInt16(3));word(UInt16(2));word(UInt32(44100));word(UInt32(44100*8));word(UInt16(8));word(UInt16(32))
        data.append(contentsOf:"data".utf8);word(UInt32(samples.count*4))
        for (index,sample) in samples.enumerated() {
            if index%8192==0 {try Task.checkCancellation()}
            word((sample*gain).bitPattern)
        }
        try data.write(to:url,options:.withoutOverwriting)
        let h=try FileHandle(forWritingTo:url);try h.synchronize();try h.close()
    }
    static func validWAV(_ url:URL,frames:Int,sha:String) throws -> Bool {
        var data=Data()
        try RetainedMediaReader.read(url,maximumBytes:Int64(44+frames*8)){data.append($0)}
        guard data.count==44+frames*8,
              String(data:data[0..<4],encoding:.ascii)=="RIFF",
              String(data:data[8..<16],encoding:.ascii)=="WAVEfmt ",
              String(data:data[36..<40],encoding:.ascii)=="data" else {return false}
        func u32(_ offset:Int)->UInt32 {data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset,as:UInt32.self)}.littleEndian}
        func u16(_ offset:Int)->UInt16 {data.withUnsafeBytes{$0.loadUnaligned(fromByteOffset:offset,as:UInt16.self)}.littleEndian}
        guard u32(4)==UInt32(data.count-8),u32(16)==16,u16(20)==3,u16(22)==2,
              u32(24)==44100,u32(28)==352800,u16(32)==8,u16(34)==32,u32(40)==UInt32(frames*8),
              SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==sha else {return false}
        for i in 0..<frames*2 {
            if i%8192==0 {try Task.checkCancellation()}
            let sample=Float(bitPattern:u32(44+i*4))
            guard sample.isFinite,abs(sample)<=1.000001 else {return false}
        }
        return true
    }
    func results() throws -> [Result] {
        try prepare()
        let children=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)
        guard children.count<=64 else {throw Failure.bounds}
        var results:[Result]=[]
        for directory in children where directory.lastPathComponent.hasPrefix("Result-") {
            try Task.checkCancellation()
            do {
                var st=stat()
                guard lstat(directory.path,&st)==0,st.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR) else {continue}
                var data=Data()
                try RetainedMediaReader.read(directory.appendingPathComponent("receipt.json"),maximumBytes:4096){data.append($0)}
                let r=try JSONDecoder().decode(Receipt.self,from:data)
                guard directory.lastPathComponent=="Result-"+r.id.uuidString,(1...441000).contains(r.frames),r.gain.isFinite,r.gain>0,r.gain<=1 else {continue}
                let result=Result(receipt:r,directory:directory)
                guard try Self.validWAV(result.vocals,frames:r.frames,sha:r.vocalsSHA256),
                      try Self.validWAV(result.accompaniment,frames:r.frames,sha:r.accompanimentSHA256) else {continue}
                results.append(result)
            } catch is CancellationError {throw CancellationError()}
            catch {continue} // Corrupt/partial entries are preserved, never offered for playback.
        }
        return results.sorted{$0.receipt.date>$1.receipt.date}
    }
}
