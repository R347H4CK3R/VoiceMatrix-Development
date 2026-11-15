import Foundation

/// Bounded private snapshot of a trusted little-endian float32 vector bank.
/// This is storage infrastructure, not model admission: callers must pin provenance
/// and supply a real streaming SHA256 accumulator. No asset allowlist is widened.
final class RVCDiskVectorBank {
    enum Failure:Error {case invalidFile, invalidValue, invalidRow}
    static let dimensions=768
    static let blockRows=16
    let count:Int
    private let handle:FileHandle
    private let lock=NSLock()
    private var cachedBlock = -1
    private var cached=Data()
    private init(handle:FileHandle,count:Int) {self.handle=handle;self.count=count}
    deinit {try? handle.close()}
    static func snapshot(source:URL,cache:URL,count:Int,expectedSHA256:String,
                         update:(Data)throws->Void,finish:()throws->String) throws -> RVCDiskVectorBank {
        guard (8...50000).contains(count),source.isFileURL,cache.isFileURL,
              expectedSHA256.count==64,expectedSHA256.allSatisfy({"0123456789abcdef".contains($0)}
              ) else {throw Failure.invalidFile}
        let info=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        let bytes=count*dimensions*4
        guard info.isRegularFile==true,info.isSymbolicLink != true,info.fileSize==bytes else {throw Failure.invalidFile}
        let fm=FileManager.default
        let folder=cache.appendingPathComponent("rvc-vectors-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {try? fm.removeItem(at:folder)}
        let target=folder.appendingPathComponent("vectors.f32")
        guard fm.createFile(atPath:target.path,contents:nil,attributes:[.posixPermissions:0o600]) else {throw Failure.invalidFile}
        let input=try FileHandle(forReadingFrom:source);defer {try? input.close()}
        let output=try FileHandle(forWritingTo:target);defer {try? output.close()}
        var total=0
        while true {
            try Task.checkCancellation()
            let data=try input.read(upToCount:blockRows*dimensions*4) ?? Data()
            if data.isEmpty {break}
            total += data.count
            guard total<=bytes,data.count%4==0 else {throw Failure.invalidFile}
            let finite=data.withUnsafeBytes { raw in
                stride(from:0,to:data.count,by:4).allSatisfy {
                    Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0,as:UInt32.self))).isFinite
                }
            }
            guard finite else {throw Failure.invalidValue}
            try update(data);try output.write(contentsOf:data)
        }
        guard total==bytes,try finish()==expectedSHA256 else {throw Failure.invalidFile}
        try Task.checkCancellation()
        try output.synchronize()
        try Task.checkCancellation()
        let reader=try FileHandle(forReadingFrom:target)
        do {
            // The verified inode remains open; no caller can reopen its pathname.
            try fm.removeItem(at:target)
            return RVCDiskVectorBank(handle:reader,count:count)
        } catch {try? reader.close();throw error}
    }
    func row(_ id:Int) throws -> [Float] {
        try Task.checkCancellation()
        guard (0..<count).contains(id) else {throw Failure.invalidRow}
        lock.lock();defer {lock.unlock()}
        let block=id/Self.blockRows
        if cachedBlock != block {
            let start=block*Self.blockRows
            let bytes=min(Self.blockRows,count-start)*Self.dimensions*4
            try handle.seek(toOffset:UInt64(start*Self.dimensions*4))
            let data=try handle.read(upToCount:bytes) ?? Data()
            guard data.count==bytes else {throw Failure.invalidFile}
            cached=data;cachedBlock=block
        }
        let offset=(id%Self.blockRows)*Self.dimensions*4
        return cached.withUnsafeBytes {raw in
            (0..<Self.dimensions).map {
                Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:offset+$0*4,as:UInt32.self)))
            }
        }
    }
}
