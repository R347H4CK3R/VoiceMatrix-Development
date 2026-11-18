import Foundation
import CryptoKit
import Darwin

struct ProbeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

@main struct Probe {
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try value() else { throw ProbeFailure(message) }
    }
    static func rejects<T>(_ message: String, _ operation: () throws -> T) throws {
        var rejected = false
        do { _ = try operation() } catch { rejected = true }
        try require(rejected, message)
    }
    static func wave() -> Data {
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        let frames = 1600
        text("RIFF"); u32(UInt32(36 + frames * 2)); text("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(16000); u32(32000); u16(2); u16(16)
        text("data"); u32(UInt32(frames * 2))
        for i in 0..<frames { u16(UInt16(bitPattern: Int16((i % 101) - 50))) }
        return data
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func context(name: String = "Original diagnostic input.wav", inputHash: String = String(repeating: "a", count: 64),
                        inputBytes: Int64 = 3244, models: [String:String] = ["hubert":String(repeating:"b",count:64), "synthesizer":String(repeating:"c",count:64)],
                        indexRate: Float = 0, semitones: Double = 0, elapsed: Double = 42) -> RVCResultHistory.Context {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        return .init(inputName: name, inputSHA256: inputHash, inputBytes: inputBytes, modelSHA256: models,
                     settings: .init(indexRate: indexRate, semitones: semitones, refinePitch: false),
                     startedAt: start, completedAt: start.addingTimeInterval(elapsed))
    }
    static func output(_ root: URL) -> URL {
        root.appendingPathComponent("RVC-preview-" + UUID().uuidString + ".wav")
    }
    static func receiptURL(_ output: URL) -> URL {
        output.deletingPathExtension().appendingPathExtension("json")
    }
    static func edit(_ path: URL, _ update: (inout [String:Any]) -> Void) throws {
        var value = try JSONSerialization.jsonObject(with: Data(contentsOf: path)) as! [String:Any]
        update(&value)
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]).write(to: path)
    }
    static func root(_ base: URL, _ name: String) throws -> URL {
        let url = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
    static func run(_ name: String, _ base: URL) async throws {
        let directory = try root(base, "Results")
        let store = try RVCResultHistory(root: directory)
        let file = output(directory)
        let original = wave()
        try original.write(to: file, options: .withoutOverwriting)
        switch name {
        case "roundtrip":
            let published = try store.publish(output: file, context: context())
            try require(published.file == file.lastPathComponent, "Receipt must bind the relative owned file")
            try require(published.bytes == original.count, "Receipt byte length")
            try require(published.sha256 == digest(original), "Receipt must contain actual output SHA256")
            try require(published.elapsedSeconds == 42, "Elapsed operation time was lost")
            let reopened = try RVCResultHistory(root: directory)
            let listing = try reopened.list()
            try require(listing.receipts.count == 1 && listing.rejected == 0 && listing.unindexed == 0, "Relaunch inventory differs")
            try require(listing.receipts[0] == published, "Receipt changes across relaunch")
            let verified = try reopened.verify(published)
            try require(verified.standardizedFileURL == file.standardizedFileURL, "Verification returned wrong file")
            try require(try Data(contentsOf: file) == original, "Publish modified output")
        case "corruption":
            let receipt = try store.publish(output: file, context: context())
            var changed = original; changed[changed.count - 1] ^= 1
            try changed.write(to: file)
            try rejects("Changed digest must fail verification") { try store.verify(receipt) }
            try require(try Data(contentsOf: file) == changed, "Corruption handling removed or rewrote output")
            try require(FileManager.default.fileExists(atPath: receiptURL(file).path), "Corruption deleted receipt")
        case "receipt-change":
            let receipt = try store.publish(output: file, context: context())
            try edit(receiptURL(file)) { value in
                var context = value["context"] as! [String:Any]
                context["inputName"] = "Changed after listing.wav"
                value["context"] = context
            }
            try rejects("Verification must reread receipt, not trust a stale selected object") { try store.verify(receipt) }
            try require(try Data(contentsOf: file) == original, "Receipt change handling touched output")
        case "traversal":
            let receipt = try store.publish(output: file, context: context())
            let outside = base.appendingPathComponent("outside.wav")
            try original.write(to: outside)
            try edit(receiptURL(file)) { $0["file"] = "../outside.wav" }
            try rejects("Receipt path escape must fail") { try store.verify(receipt) }
            let listing = try store.list()
            try require(listing.receipts.isEmpty && listing.rejected >= 1, "Unsafe receipt entered history")
            try require(try Data(contentsOf: outside) == original, "Outside file changed")
            try require(try Data(contentsOf: file) == original, "Original changed")
        case "unsafe-files":
            let outside = base.appendingPathComponent("outside.wav")
            try original.write(to: outside)
            let link = output(directory)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            try rejects("Symlink output must not publish") { try store.publish(output: link, context: context()) }
            let fifo = output(directory)
            try require(mkfifo(fifo.path, mode_t(0o600)) == 0, "Cannot construct FIFO")
            try rejects("FIFO output must not publish or block") { try store.publish(output: fifo, context: context()) }
            let receipt = try store.publish(output: file, context: context())
            let stored = receiptURL(file), saved = base.appendingPathComponent("receipt-source.json")
            try FileManager.default.moveItem(at: stored, to: saved)
            try FileManager.default.createSymbolicLink(at: stored, withDestinationURL: saved)
            try rejects("Symlink receipt must fail verification") { try store.verify(receipt) }
            try require((try store.list()).rejected >= 1, "Unsafe receipt must be accounted for")
            let rootLink = base.appendingPathComponent("LinkedResults")
            try FileManager.default.createSymbolicLink(at: rootLink, withDestinationURL: directory)
            try rejects("Symlink root must fail") { try RVCResultHistory(root: rootLink).list() }
            try require(try Data(contentsOf: outside) == original, "Unsafe file handling touched external source")
        case "unindexed":
            let unrelated = directory.appendingPathComponent("user-note.txt")
            let content = Data("Never delete me".utf8)
            try content.write(to: unrelated)
            let listing = try store.list()
            try require(listing.receipts.isEmpty && listing.unindexed == 1, "Completed file without receipt must be recognized as unindexed")
            try require(try Data(contentsOf: file) == original, "Unindexed result changed")
            try require(try Data(contentsOf: unrelated) == content, "Unrelated file changed")
        case "overwrite":
            let receipt = try store.publish(output: file, context: context())
            let saved = try Data(contentsOf: receiptURL(file))
            try rejects("Existing receipt must not be overwritten") { try store.publish(output: file, context: context(name: "Replacement.wav")) }
            try require(try Data(contentsOf: receiptURL(file)) == saved, "Existing receipt changed")
            try require(try Data(contentsOf: file) == original, "Existing output changed")
            _ = try store.verify(receipt)
        case "metadata":
            let invalid = [context(inputHash: "../bad"), context(inputBytes: 0), context(name: String(repeating: "x", count: 121)),
                           context(models: ["hubert":String(repeating:"b",count:64)]), context(models: ["hubert":String(repeating:"b",count:64), "synthesizer":String(repeating:"c",count:64), "foreign":String(repeating:"d",count:64)]),
                           context(indexRate: -0.1), context(indexRate: .nan), context(semitones: 25), context(semitones: .infinity), context(elapsed: -1), context(elapsed: 86401)]
            for candidate in invalid {
                try rejects("Invalid context must fail publication") { try store.publish(output: file, context: candidate) }
                try require(!FileManager.default.fileExists(atPath: receiptURL(file).path), "Invalid metadata committed receipt")
            }
            try require(try Data(contentsOf: file) == original, "Invalid metadata removed completed file")
        case "invalid-wav":
            for contents in [Data("not a wave".utf8), Data(original.prefix(44)), Data(original.dropLast())] {
                let candidate = output(directory)
                try contents.write(to: candidate)
                try rejects("Incomplete WAV must not publish") { try store.publish(output: candidate, context: context()) }
                try require(try Data(contentsOf: candidate) == contents, "Invalid WAV was deleted")
                try require(!FileManager.default.fileExists(atPath: receiptURL(candidate).path), "Invalid WAV got a receipt")
            }
        case "bounds":
            let receipt = try store.publish(output: file, context: context())
            let template = try Data(contentsOf: receiptURL(file))
            let crowded = try root(base, "TooManyReceipts")
            for _ in 0..<201 {
                let item = output(crowded)
                try original.write(to: item)
                var value = try JSONSerialization.jsonObject(with: template) as! [String:Any]
                value["id"] = String(item.deletingPathExtension().lastPathComponent.dropFirst("RVC-preview-".count))
                value["file"] = item.lastPathComponent
                try JSONSerialization.data(withJSONObject: value).write(to: receiptURL(item))
            }
            try rejects("History exceeding 200 receipts must fail closed, not return a partial list") { try RVCResultHistory(root: crowded).list() }
            try require(try FileManager.default.contentsOfDirectory(atPath: crowded.path).count == 402, "History bound deleted files")
            try Data(repeating: 32, count: 16_385).write(to: receiptURL(file))
            try rejects("Oversized receipt must fail") { try store.verify(receipt) }
            try require((try store.list()).rejected >= 1, "Oversized receipt silently admitted")
            let busy = try root(base, "Overfull")
            for i in 0..<1025 { try Data().write(to: busy.appendingPathComponent("unrelated-\(i)")) }
            try rejects("Directory scanning must be bounded") { try RVCResultHistory(root: busy).list() }
            try require(try FileManager.default.contentsOfDirectory(atPath: busy.path).count == 1025, "Bound check deleted files")
        case "cancellation":
            withUnsafeCurrentTask { $0?.cancel() }
            try rejects("Cancelled publish must not advertise output") { try store.publish(output: file, context: context()) }
            try require(!FileManager.default.fileExists(atPath: receiptURL(file).path), "Cancelled publish committed receipt")
            try require(try Data(contentsOf: file) == original, "Cancellation deleted completed result")
        case "commit-state":
            var state=RVCPreviewState()
            let ticket=try state.begin(.conversion)
            state.requestCancel()
            state.finishCommitted(ticket:ticket)
            try require(state.phase == .succeeded && state.percent == 100,"Durable commit must win late cancellation")
            state.finishCommitted(ticket:UUID())
            try require(state.phase == .succeeded,"Stale ticket changed committed state")
        case "late-cancellation":
            _ = try store.publish(output: file, context: context())
            let committed = try Data(contentsOf: receiptURL(file))
            withUnsafeCurrentTask { $0?.cancel() }
            try rejects("A later cancelled operation must reject") { try store.publish(output: file, context: context()) }
            try require(try Data(contentsOf: receiptURL(file)) == committed, "Late cancellation removed committed receipt")
            try require(try Data(contentsOf: file) == original, "Late cancellation removed completed output")
        case "snapshot-reuse":
            let receipt=try store.publish(output:file,context:context())
            let cache=try root(base,"Cache")
            let first=try store.snapshot(receipt,cache:cache)
            for _ in 0..<12 {try require(try store.snapshot(receipt,cache:cache)==first,"Reopening must reuse same verified copy")}
            try require(try FileManager.default.contentsOfDirectory(atPath:cache.path).count==1,"Repeated opens consumed storage slots")
            var corrupt=original;corrupt[corrupt.count-1] ^= 1
            try corrupt.write(to:first)
            try rejects("Corrupt existing snapshot must fail closed") {try store.snapshot(receipt,cache:cache)}
            try require(try Data(contentsOf:first)==corrupt,"Corrupt snapshot was overwritten")
            try FileManager.default.removeItem(at:first)
            try FileManager.default.createSymbolicLink(at:first,withDestinationURL:file)
            try rejects("Symlink snapshot must be rejected") {try store.snapshot(receipt,cache:cache)}
            try require(try Data(contentsOf:file)==original,"Source was changed by rejected snapshot")
        case "snapshot-crash":
            let receipt=try store.publish(output:file,context:context())
            let cache=try root(base,"Cache")
            let empty=cache.appendingPathComponent(".rvc-action-staging-"+UUID().uuidString,isDirectory:true)
            let partial=cache.appendingPathComponent(".rvc-action-staging-"+UUID().uuidString,isDirectory:true)
            try FileManager.default.createDirectory(at:empty,withIntermediateDirectories:false)
            try FileManager.default.createDirectory(at:partial,withIntermediateDirectories:false)
            let partialFile=partial.appendingPathComponent(file.lastPathComponent)
            let partialBytes=Data(original.prefix(19));try partialBytes.write(to:partialFile)
            let selected=try store.snapshot(receipt,cache:cache)
            try require(try Data(contentsOf:selected)==original,"Interrupted staging blocked new verified snapshot")
            try require(FileManager.default.fileExists(atPath:empty.path),"Empty staging was deleted")
            try require(try Data(contentsOf:partialFile)==partialBytes,"Partial staging was changed")
            try require(!selected.path.contains(".rvc-action-staging-"),"Uncommitted staging escaped as playable")
            let broken=cache.appendingPathComponent("rvc-action-unrelated-empty",isDirectory:true)
            try FileManager.default.createDirectory(at:broken,withIntermediateDirectories:false)
            let reopened=try RVCResultHistory(root:directory).snapshot(receipt,cache:cache)
            try require(reopened==selected,"Unrelated corrupt cache blocked existing verified result")
            try require(try Data(contentsOf:file)==original,"Crash recovery changed saved result")
            let other=output(directory);try original.write(to:other)
            let otherReceipt=try store.publish(output:other,context:context())
            let conflict=cache.appendingPathComponent("rvc-action-"+otherReceipt.id.uuidString.lowercased()+"-"+otherReceipt.sha256,isDirectory:true)
            try FileManager.default.createDirectory(at:conflict,withIntermediateDirectories:false)
            try rejects("Even an empty final destination must not be overwritten") {try store.snapshot(otherReceipt,cache:cache)}
            try require(try FileManager.default.contentsOfDirectory(atPath:conflict.path).isEmpty,"Final destination conflict was overwritten")
            try require(try Data(contentsOf:other)==original,"Final conflict modified saved WAV")
        case "mixed-history":
            let valid=try store.publish(output:file,context:context())
            let bad=output(directory);try original.write(to:bad)
            try Data("broken receipt".utf8).write(to:receiptURL(bad))
            let listing=try store.list()
            try require(listing.receipts==[valid] && listing.rejected==1 && listing.unindexed==1,"Corrupt record hid valid history")
            let next=output(directory);try original.write(to:next)
            try FileManager.default.createDirectory(at:receiptURL(next),withIntermediateDirectories:false)
            try rejects("Receipt publication obstruction must fail") {try store.publish(output:next,context:context())}
            try require(try Data(contentsOf:next)==original,"Failed receipt publication deleted completed WAV")
            try require(try store.verify(valid)==file,"Failed publication invalidated prior result")
        case "snapshot":
            let receipt = try store.publish(output: file, context: context())
            let cache = try root(base, "Cache")
            let selected = try store.snapshot(receipt, cache: cache)
            try require(selected.standardizedFileURL != file.standardizedFileURL, "Playback must use a verified private copy")
            try require(try Data(contentsOf: selected) == original, "Snapshot bytes differ")
            var changed = original; changed[changed.count - 1] ^= 1
            try changed.write(to: file)
            try require(try Data(contentsOf: selected) == original, "Original mutation changed playback snapshot")
            try rejects("Changed source must not create new selection snapshot") { try store.snapshot(receipt, cache: cache) }
            try require(try Data(contentsOf: file) == changed, "Rejected selection changed source")
        default: throw ProbeFailure("Unknown case")
        }
    }
    static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count == 3 else { throw ProbeFailure("case and test directory required") }
            try await run(args[1], URL(fileURLWithPath: args[2], isDirectory: true))
            print("HISTORY_CASE_PASSED " + args[1])
        } catch {
            FileHandle.standardError.write(Data(("HISTORY_CASE_FAILED \(error)\n").utf8))
            exit(1)
        }
    }
}
