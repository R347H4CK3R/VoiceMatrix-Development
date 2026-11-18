#if canImport(AVFoundation)
import Foundation
import CryptoKit
import AVFoundation
#if canImport(Darwin)
import Darwin
#endif

/// Explicit, bounded retained-source clip preparation. Does not run any model.
enum SeparationClipHandoff {
    struct Source: Hashable {
        let jobID: UUID
        let url: URL
        let sha256: String
    }
    struct Receipt: Codable, Equatable {
        let id: UUID
        let sourceJobID: UUID
        let sourceSHA256: String
        let requestedStart: Double
        let requestedSeconds: Double
        let actualStart: Double
        let frames: Int
        let clipSHA256: String
    }
    struct Input: Identifiable, Hashable {
        let id: UUID
        let url: URL
        let sha256: String
        let receiptSHA256: String
        let start: Double
        let frames: Int
    }
    /// Crash remnants are retained, but cannot consume unbounded snapshot space.
    static func admitScratch(store:SeparationStore) throws {
        let children=try FileManager.default.contentsOfDirectory(at:store.root,includingPropertiesForKeys:nil)
        guard children.count<64 else {throw SeparationStore.Failure.bounds}
        var total:Int64=0
        for directory in children where directory.lastPathComponent.hasPrefix(".clip-staging-") {
            try Task.checkCancellation()
            var info=stat()
            guard lstat(directory.path,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR) else {throw SeparationStore.Failure.unsafe}
            let files=try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil)
            guard files.count<=3 else {throw SeparationStore.Failure.bounds}
            for file in files {
                guard lstat(file.path,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),
                      info.st_size>=0,info.st_size<=536_870_912 else {throw SeparationStore.Failure.unsafe}
                total += Int64(info.st_size)
                // Reserve the full source plus canonical WAV/receipt for this attempt.
                guard total<=1_073_741_824-541_000_000 else {throw SeparationStore.Failure.bounds}
            }
        }
    }
    static func prepare(source: Source, start: Double, seconds: Double,
                        store: SeparationStore = .standard) async throws -> Input {
        guard source.url.isFileURL, source.sha256.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil,
              start.isFinite, seconds.isFinite, start>=0, (0.5...10).contains(seconds), start+seconds<=1800 else {throw SeparationStore.Failure.invalid}
        try Task.checkCancellation();try store.admit();try admitScratch(store:store)
        let space=try FileManager.default.attributesOfFileSystem(forPath:store.root.path)
        guard let free=space[.systemFreeSize] as? NSNumber, free.int64Value>800_000_000 else {throw SeparationStore.Failure.storage}
        let id=UUID(), staging=store.root.appendingPathComponent(".clip-staging-"+UUID().uuidString,isDirectory:true)
        let destination=store.root.appendingPathComponent("Clip-"+id.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {try? FileManager.default.removeItem(at:staging)}
        let snapshot=staging.appendingPathComponent("source").appendingPathExtension(source.url.pathExtension)
        try Data().write(to:snapshot,options:.withoutOverwriting)
        let writer=try FileHandle(forWritingTo:snapshot)
        do {
            var hash=SHA256()
            try RetainedMediaReader.read(source.url,maximumBytes:536_870_912) {data in
                hash.update(data:data);try writer.write(contentsOf:data)
            }
            try writer.synchronize();try writer.close()
            guard hash.finalize().map({String(format:"%02x",$0)}).joined()==source.sha256 else {throw SeparationStore.Failure.unsafe}
        } catch {try? writer.close();throw error}
        try Task.checkCancellation()
        let clip=try await SeparationClipExtractor.extract(source:snapshot,start:start,seconds:seconds)
        guard try SeparationStore.digest(snapshot,maximum:536_870_912)==source.sha256 else {throw SeparationStore.Failure.unsafe}
        let wave=staging.appendingPathComponent("clip.wav")
        try SeparationStore.writeWAV(clip.samples,gain:1,to:wave)
        let sha=try SeparationStore.digest(wave,maximum:4_000_000)
        guard try SeparationStore.validWAV(wave,frames:clip.frames,sha:sha) else {throw SeparationStore.Failure.invalid}
        let receipt=Receipt(id:id,sourceJobID:source.jobID,sourceSHA256:source.sha256,
                            requestedStart:start,requestedSeconds:seconds,actualStart:clip.start,frames:clip.frames,clipSHA256:sha)
        let receiptData=try JSONEncoder().encode(receipt)
        let metadata=staging.appendingPathComponent("receipt.json")
        try receiptData.write(to:metadata,options:.withoutOverwriting)
        let handle=try FileHandle(forWritingTo:metadata);try handle.synchronize();try handle.close()
        let receiptSHA=SHA256.hash(data:receiptData).map{String(format:"%02x",$0)}.joined()
        try FileManager.default.removeItem(at:snapshot) // Only the private verified scratch copy.
        try Task.checkCancellation()
        guard renamex_np(staging.path,destination.path,UInt32(RENAME_EXCL))==0 else {throw SeparationStore.Failure.storage}
        return Input(id:id,url:destination.appendingPathComponent("clip.wav"),sha256:sha,
                     receiptSHA256:receiptSHA,start:clip.start,frames:clip.frames)
    }
    /// Recheck the canonical owned clip and bounded provenance on destination entry.
    static func validate(_ input:Input, store:SeparationStore = .standard) throws {
        try Task.checkCancellation();try store.prepare()
        let directory=store.root.appendingPathComponent("Clip-"+input.id.uuidString,isDirectory:true)
        guard input.url.lastPathComponent=="clip.wav",
              input.url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == directory.resolvingSymlinksInPath().standardizedFileURL.path else {throw SeparationStore.Failure.unsafe}
        var info=stat()
        guard lstat(directory.path,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR) else {throw SeparationStore.Failure.unsafe}
        var data=Data()
        try RetainedMediaReader.read(directory.appendingPathComponent("receipt.json"),maximumBytes:4096){data.append($0)}
        guard SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined()==input.receiptSHA256 else {throw SeparationStore.Failure.unsafe}
        let receipt=try JSONDecoder().decode(Receipt.self,from:data)
        guard receipt.id==input.id,receipt.clipSHA256==input.sha256,receipt.frames==input.frames,
              (1...441000).contains(input.frames),receipt.actualStart==input.start,
              try SeparationStore.validWAV(directory.appendingPathComponent("clip.wav"),frames:input.frames,sha:input.sha256) else {throw SeparationStore.Failure.unsafe}
    }
}
#endif
