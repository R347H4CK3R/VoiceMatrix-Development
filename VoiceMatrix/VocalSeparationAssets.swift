import Foundation
#if canImport(CryptoKit)
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Receipts/manifests cannot authorize arbitrary models. These bytes are fixed in source.
enum VocalSeparationAssets {
    enum Failure:Error {case unsafe,invalidModel,bounds}
    static let models:[String:(bytes:Int64,sha256:String)] = [
        "vocals.onnx":(39318336,"bdc16ab6bf6117ddd4842c19e80e40e2be188fc555295064d424616b0224ac97"),
        "accompaniment.onnx":(39318343,"671ace17acd3720674a2bc14de32ac6292453dec20d9eb0ba4255d4ad8e3d8c0")
    ]
    static func directory(_ url:URL) throws {
        var info=stat()
        guard url.isFileURL,lstat(url.path,&info)==0,info.st_mode & mode_t(S_IFMT)==mode_t(S_IFDIR) else {throw Failure.unsafe}
    }
    static func validate(root:URL) throws {
        try directory(root)
        for (name,expected) in models {
            var hash=SHA256()
            let bytes=try RetainedMediaReader.read(root.appendingPathComponent(name),maximumBytes:expected.bytes){hash.update(data:$0)}
            guard bytes==expected.bytes,hash.finalize().map({String(format:"%02x",$0)}).joined()==expected.sha256 else {throw Failure.invalidModel}
        }
    }
    static func snapshot(root:URL,cache:URL) throws -> URL {
        try Task.checkCancellation();try directory(root);try directory(cache)
        let space=try FileManager.default.attributesOfFileSystem(forPath:cache.path)
        guard let available=space[.systemFreeSize] as? NSNumber,available.int64Value>150_000_000 else {throw Failure.bounds}
        let output=cache.appendingPathComponent("separation-models-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var success=false
        defer {if !success {try? FileManager.default.removeItem(at:output)}}
        for (name,expected) in models {
            let destination=output.appendingPathComponent(name)
            try Data().write(to:destination,options:.withoutOverwriting)
            let handle=try FileHandle(forWritingTo:destination)
            do {
                var hash=SHA256()
                let bytes=try RetainedMediaReader.read(root.appendingPathComponent(name),maximumBytes:expected.bytes){chunk in
                    hash.update(data:chunk);try handle.write(contentsOf:chunk)
                }
                guard bytes==expected.bytes,hash.finalize().map({String(format:"%02x",$0)}).joined()==expected.sha256 else {throw Failure.invalidModel}
                try handle.synchronize();try handle.close()
            } catch {try? handle.close();throw error}
        }
        try Task.checkCancellation();success=true;return output
    }
}
#endif
