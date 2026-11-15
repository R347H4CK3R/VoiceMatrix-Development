#if os(iOS)
import Foundation
import CryptoKit
import AVFoundation

enum RVCPreviewPack:String,CaseIterable,Identifiable {
    case hubert,synthesizer,retrieval
    var id:String {rawValue}
    var title:String {
        switch self {case .hubert:return "Speech encoder";case .synthesizer:return "Evaluation voice model";case .retrieval:return "Retrieval data"}
    }
}
enum RVCPreviewStore {
    static var root:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("RVCPreview",isDirectory:true)}
    static var cache:URL {FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0].appendingPathComponent("RVCPreview",isDirectory:true)}
    static var results:URL {root.appendingPathComponent("Results",isDirectory:true)}
    static func prepare() throws {
        for url in [root,cache,results,root.appendingPathComponent("Inputs")] {
            try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        }
    }
    static func locations() throws -> [RVCPreviewPack:URL] {
        let url=root.appendingPathComponent("installed.json")
        guard FileManager.default.fileExists(atPath:url.path) else {return [:]}
        guard try RVCSynthesisAssets.regularFile(url)<=4096 else {throw RVCSynthesisFailure.invalidAsset}
        let data=try Data(contentsOf:url)
        let map=try JSONDecoder().decode([String:String].self,from:data)
        var result:[RVCPreviewPack:URL]=[:]
        for (key,value) in map {
            guard let role=RVCPreviewPack(rawValue:key),RVCPreviewState.validPackFolder(value) else {throw RVCSynthesisFailure.invalidAsset}
            let folder=root.appendingPathComponent(value,isDirectory:true)
            if FileManager.default.fileExists(atPath:folder.path) {result[role]=folder}
        }
        return result
    }
    static func copyBounded(_ source:URL,to target:URL,maximum:Int,exact:Int?=nil) throws {
        let size=try RVCSynthesisAssets.regularFile(source)
        guard size>0,size<=maximum,exact==nil || exact==size else {throw RVCFileError.bounds}
        let input=try FileHandle(forReadingFrom:source);defer{try? input.close()}
        let output=try RVCFileIO.create(target);defer{try? output.close()}
        var count=0
        while true {
            try Task.checkCancellation()
            let data=try input.read(upToCount:1024*1024) ?? Data()
            if data.isEmpty {break}
            count += data.count;guard count<=size else {throw RVCFileError.bounds}
            try output.write(contentsOf:data)
        }
        guard count==size else {throw RVCFileError.format}
        try output.synchronize()
    }
    static func install(_ role:RVCPreviewPack,from source:URL) throws {
        try prepare()
        let scoped=source.startAccessingSecurityScopedResource()
        defer{if scoped {source.stopAccessingSecurityScopedResource()}}
        let folder:URL
        if role == .retrieval {
            let descriptor=try RVCRetrievalAssets.descriptor(at:source)
            folder=root.appendingPathComponent("rvc-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            do {
                for file in descriptor.files {
                    try copyBounded(source.appendingPathComponent(file.name),to:folder.appendingPathComponent(file.name),maximum:file.bytes,exact:file.bytes)
                }
                let manifest=RVCRetrievalAssets.Manifest(schemaVersion:1,profile:descriptor.profile)
                try JSONEncoder().encode(manifest).write(to:folder.appendingPathComponent("manifest.json"),options:.withoutOverwriting)
                _=try RVCNativeRetrieval.loadVerifiedPack(at:folder,cache:cache,expectedProfile:descriptor.profile)
            } catch {try? FileManager.default.removeItem(at:folder);throw error}
        } else {
            let manifest=try RVCSynthesisAssets.manifest(at:source)
            let profile=role == .hubert ? "hubert-147680-cpu" : "rvc-v2-922-cpu"
            var digest=SHA256()
            let model=try RVCSynthesisAssets.snapshot(root:source,cache:root,profile:profile,update:{digest.update(data:$0)},finish:{digest.finalize().map{String(format:"%02x",$0)}.joined()})
            folder=model.deletingLastPathComponent()
            do {try JSONEncoder().encode(manifest).write(to:folder.appendingPathComponent("manifest.json"),options:.withoutOverwriting)}
            catch {try? FileManager.default.removeItem(at:folder);throw error}
        }
        var committed=false
        defer{if !committed {try? FileManager.default.removeItem(at:folder)}}
        try Task.checkCancellation()
        var current=(try? locations()) ?? [:]
        let previous=current[role]
        current[role]=folder
        let mapping=Dictionary(uniqueKeysWithValues:current.map{($0.key.rawValue,$0.value.lastPathComponent)})
        try JSONEncoder().encode(mapping).write(to:root.appendingPathComponent("installed.json"),options:.atomic)
        committed=true
        // Only replace this feature's own prior generated pack; never a source/library folder.
        if let previous,previous != folder {try? FileManager.default.removeItem(at:previous)}
    }
    static func importAudio(_ source:URL) throws -> URL {
        try prepare()
        let scoped=source.startAccessingSecurityScopedResource()
        defer{if scoped {source.stopAccessingSecurityScopedResource()}}
        let allowed=["wav","m4a","caf","mp3","aif","aiff","flac","aac"]
        let ext=source.pathExtension.lowercased()
        guard allowed.contains(ext) else {throw RVCFileError.format}
        let target=root.appendingPathComponent("Inputs").appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
        do {
            try copyBounded(source,to:target,maximum:800_000_000)
            let file=try AVAudioFile(forReading:target)
            let rate=file.processingFormat.sampleRate
            guard rate.isFinite,rate>0,file.length>0,Double(file.length)/rate<=7200,
                  (1...2).contains(file.processingFormat.channelCount) else {throw RVCFileError.bounds}
            try Task.checkCancellation()
            return target
        } catch {try? FileManager.default.removeItem(at:target);throw error}
    }
}
#endif
