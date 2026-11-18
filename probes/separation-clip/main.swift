import Foundation
import Darwin

@main struct Probe {
    static func require(_ condition:Bool,_ message:String) throws {
        if !condition {throw NSError(domain:message,code:1)}
    }
    static func handoff(mode:String,source:URL,start:Double,seconds:Double,root:URL) async throws {
        let sha=try SeparationStore.digest(source,maximum:536_870_912)
        let store=SeparationStore(root:root)
        if mode=="handoff-cancel" {withUnsafeCurrentTask {$0?.cancel()}}
        let inputSource=SeparationClipHandoff.Source(jobID:UUID(),url:source,sha256:mode=="handoff-wrong-sha" ? String(repeating:"0",count:64) : sha)
        if mode=="handoff-wrong-sha" || mode=="handoff-cancel" {
            var rejected=false
            do {_ = try await SeparationClipHandoff.prepare(source:inputSource,start:start,seconds:seconds,store:store)} catch {rejected=true}
            try require(rejected,"Unsafe handoff succeeded")
            let children=(try? FileManager.default.contentsOfDirectory(atPath:root.path)) ?? []
            try require(!children.contains(where:{$0.hasPrefix("Clip-") || $0.hasPrefix(".clip-staging-")}),"Failed handoff retained output")
            print("{\"checked\":true,\"clips\":0}")
            return
        }
        let input=try await SeparationClipHandoff.prepare(source:inputSource,start:start,seconds:seconds,store:store)
        try SeparationClipHandoff.validate(input,store:store)
        try require(input.frames>0 && abs(input.frames-Int((seconds*44100).rounded()))<=1,"Unexpected handoff duration")
        if mode=="handoff-corrupt-clip" || mode=="handoff-corrupt-receipt" {
            let changed=mode=="handoff-corrupt-clip" ? input.url : input.url.deletingLastPathComponent().appendingPathComponent("receipt.json")
            var bytes=try Data(contentsOf:changed)
            bytes[bytes.count-1] ^= 1
            try bytes.write(to:changed)
            var rejected=false
            do {try SeparationClipHandoff.validate(input,store:store)} catch {rejected=true}
            try require(rejected,"Changed published clip or receipt was accepted")
            try require(FileManager.default.fileExists(atPath:changed.path),"Validation deleted retained evidence")
        } else {try require(mode=="handoff-good","Unknown handoff mode")}
        try require(try SeparationStore.digest(source,maximum:536_870_912)==sha,"Source was modified")
        let children=try FileManager.default.contentsOfDirectory(atPath:root.path)
        try require(children.filter{$0.hasPrefix("Clip-")}.count==1,"Unexpected published clips")
        try require(!children.contains(where:{$0.hasPrefix(".clip-staging-")}),"Scratch snapshot not removed")
        print("{\"checked\":true,\"clips\":1}")
    }
    static func scratch(mode:String,source:URL,root:URL) async throws {
        let store=SeparationStore(root:root)
        try store.prepare()
        let stage=root.appendingPathComponent(".clip-staging-crash",isDirectory:true)
        var retained:URL=stage
        if mode=="scratch-stage-link" {
            let outside=root.deletingLastPathComponent().appendingPathComponent("outside-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:outside,withIntermediateDirectories:false)
            try FileManager.default.createSymbolicLink(at:stage,withDestinationURL:outside)
            retained=outside
        } else {
            try FileManager.default.createDirectory(at:stage,withIntermediateDirectories:false)
            if mode=="scratch-sparse" {
                let file=stage.appendingPathComponent("source.mov")
                try Data().write(to:file,options:.withoutOverwriting)
                let handle=try FileHandle(forWritingTo:file)
                try handle.truncate(atOffset:533_000_000);try handle.close()
                retained=file
            } else if mode=="scratch-file-link" {
                let file=stage.appendingPathComponent("source.wav")
                try FileManager.default.createSymbolicLink(at:file,withDestinationURL:source)
                retained=file
            } else if mode=="scratch-fifo" {
                let file=stage.appendingPathComponent("source.wav")
                try require(mkfifo(file.path,0o600)==0,"Could not create test FIFO")
                retained=file
            } else if mode=="scratch-many-files" {
                for i in 0..<4 {try Data().write(to:stage.appendingPathComponent("file-\(i)"),options:.withoutOverwriting)}
            } else if mode=="scratch-many-entries" {
                for i in 0..<63 {try Data().write(to:root.appendingPathComponent("unrelated-\(i)"),options:.withoutOverwriting)}
            } else {try require(mode=="scratch-empty-repeat","Unknown scratch mode")}
        }
        if mode=="scratch-empty-repeat" {
            try SeparationClipHandoff.admitScratch(store:store)
            let sha=try SeparationStore.digest(source,maximum:536_870_912)
            let inputSource=SeparationClipHandoff.Source(jobID:UUID(),url:source,sha256:sha)
            for _ in 0..<2 {
                let input=try await SeparationClipHandoff.prepare(source:inputSource,start:0.25,seconds:0.5,store:store)
                try SeparationClipHandoff.validate(input,store:store)
            }
            let stages=try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasPrefix(".clip-staging-")}
            try require(stages==[stage.lastPathComponent],"Successful preparations leaked scratch or deleted crash stage")
            try require(try FileManager.default.contentsOfDirectory(atPath:stage.path).isEmpty,"Empty crash stage changed")
            try require(try SeparationStore.digest(source,maximum:536_870_912)==sha,"Source changed")
        } else {
            var rejected=false
            do {try SeparationClipHandoff.admitScratch(store:store)} catch {rejected=true}
            try require(rejected,"Unsafe scratch was admitted")
            var info=stat()
            try require(lstat(retained.path,&info)==0,"Admission deleted retained evidence")
            if mode=="scratch-sparse" {try require(info.st_size==533_000_000,"Sparse source changed")}
            if mode=="scratch-file-link" {try require(info.st_mode & mode_t(S_IFMT)==mode_t(S_IFLNK),"Symlink changed")}
            if mode=="scratch-fifo" {try require(info.st_mode & mode_t(S_IFMT)==mode_t(S_IFIFO),"FIFO changed")}
            let clips=try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasPrefix("Clip-")}
            try require(clips.isEmpty,"Scratch rejection published clip")
        }
        print("{\"scratchChecked\":true}")
    }
    static func main() async {
        do {
            let args=CommandLine.arguments
            guard args.count==6,let start=Double(args[3]),let duration=Double(args[4]) else {throw NSError(domain:"arguments",code:1)}
            if args[1].hasPrefix("scratch-") {
                try await scratch(mode:args[1],source:URL(fileURLWithPath:args[2]),root:URL(fileURLWithPath:args[5],isDirectory:true))
                return
            }
            if args[1]=="timeline-checks" {
                try SeparationClipExtractor.validateCoverage([(start:-1,end:1),(start:1,end:2)],start:0,end:2)
                for intervals in [[(start:-1.0,end:1.5),(start:1.0,end:2.0)],[(start:0.0,end:0.9),(start:1.0,end:2.0)]] {
                    var rejected=false
                    do {try SeparationClipExtractor.validateCoverage(intervals,start:0,end:2)} catch {rejected=true}
                    try require(rejected,"Overlapping or missing timeline accepted")
                }
                print("{\"timelineChecked\":true}");return
            }
            if args[1].hasPrefix("handoff-") {
                try await handoff(mode:args[1],source:URL(fileURLWithPath:args[2]),start:start,seconds:duration,root:URL(fileURLWithPath:args[5],isDirectory:true))
                return
            }
            if args[1]=="cancel" {withUnsafeCurrentTask {$0?.cancel()}}
            let result=try await SeparationClipExtractor.extract(source:URL(fileURLWithPath:args[2]),start:start,seconds:duration,diagnostic:{message in
                FileHandle.standardError.write(Data((message+"\n").utf8))
            })
            var data=Data(capacity:result.samples.count*4)
            for sample in result.samples {var bits=sample.bitPattern.littleEndian;withUnsafeBytes(of:&bits){data.append(contentsOf:$0)}}
            try data.write(to:URL(fileURLWithPath:args[5]),options:.withoutOverwriting)
            let metadata:[String:Any]=["frames":result.frames,"sampleRate":result.sampleRate,"start":result.start,"seconds":result.seconds]
            let json=try JSONSerialization.data(withJSONObject:metadata,options:.sortedKeys)
            print(String(decoding:json,as:UTF8.self))
        } catch {
            FileHandle.standardError.write(Data("CLIP_REJECTED \(error)\n".utf8));exit(1)
        }
    }
}
