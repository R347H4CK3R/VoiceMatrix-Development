import Foundation
#if canImport(CryptoKit)
import CryptoKit
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// Private diagnostic history only. Receipts cannot authorize models or arbitrary paths.
struct RVCResultHistory {
    enum Failure: Error { case unsafe, bounds, changed, invalid, exists }
    struct Settings: Codable, Equatable {
        let indexRate: Float
        let semitones: Double
        let refinePitch: Bool
    }
    struct Context: Codable, Equatable {
        let inputName: String
        let inputSHA256: String
        let inputBytes: Int64
        let modelSHA256: [String:String]
        let settings: Settings
        let startedAt: Date
        let completedAt: Date
    }
    struct Receipt: Codable, Equatable, Identifiable {
        let schemaVersion: Int
        let id: UUID
        let file: String
        let createdAt: Date
        let elapsedSeconds: Double
        let bytes: Int64
        let sha256: String
        let context: Context
    }
    struct Listing { let receipts: [Receipt]; let rejected: Int; let unindexed: Int }
    struct Identity { let bytes: Int64; let sha256: String }
    let root: URL
    private static let maximumBytes: Int64 = 800_000_000
    private static let maximumReceiptBytes: Int64 = 16_384

    static func identity(_ url: URL) throws -> Identity {
        var hash = SHA256()
        let bytes = try RetainedMediaReader.read(url, maximumBytes: maximumBytes) { hash.update(data:$0) }
        return Identity(bytes:bytes,sha256:hash.finalize().map { String(format:"%02x",$0) }.joined())
    }
    private func directory(_ url: URL) throws {
        guard url.isFileURL else { throw Failure.unsafe }
        var info = stat()
        guard lstat(url.path,&info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else { throw Failure.unsafe }
    }
    private func regularSize(_ url: URL, maximum: Int64) throws -> Int64 {
        var info = stat()
        guard lstat(url.path,&info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= maximum else { throw Failure.unsafe }
        return Int64(info.st_size)
    }
    private func ownedID(_ file: String) throws -> UUID {
        guard file.hasPrefix("RVC-preview-"), file.hasSuffix(".wav"), file.count == 52,
              let id = UUID(uuidString:String(file.dropFirst(12).dropLast(4))),
              file.lowercased() == "rvc-preview-" + id.uuidString.lowercased() + ".wav" else { throw Failure.unsafe }
        return id
    }
    private func receiptURL(_ file: String) throws -> URL {
        _ = try ownedID(file)
        return root.appendingPathComponent(String(file.dropLast(4)) + ".json")
    }
    private func validHash(_ text: String) -> Bool {
        text.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func validate(_ context: Context) throws {
        let elapsed = context.completedAt.timeIntervalSince(context.startedAt)
        let keys = Set(context.modelSHA256.keys)
        guard !context.inputName.isEmpty, context.inputName.count <= 120,
              context.inputName.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
              validHash(context.inputSHA256), context.inputBytes > 0, context.inputBytes <= Self.maximumBytes,
              keys == Set(["hubert","synthesizer"]) || keys == Set(["hubert","synthesizer","retrieval"]),
              context.modelSHA256.values.allSatisfy(validHash),
              context.settings.indexRate.isFinite, (0...1).contains(context.settings.indexRate),
              context.settings.semitones.isFinite, (-24...24).contains(context.settings.semitones),
              context.settings.indexRate == 0 || context.modelSHA256["retrieval"] != nil,
              context.startedAt.timeIntervalSince1970.isFinite, context.completedAt.timeIntervalSince1970.isFinite,
              elapsed.isFinite, (0...86_400).contains(elapsed) else { throw Failure.invalid }
    }
    private func validate(_ receipt: Receipt) throws {
        try validate(receipt.context)
        guard receipt.schemaVersion == 1, try ownedID(receipt.file) == receipt.id,
              receipt.createdAt == receipt.context.completedAt,
              receipt.elapsedSeconds == receipt.context.completedAt.timeIntervalSince(receipt.context.startedAt),
              receipt.bytes > 44, receipt.bytes <= Self.maximumBytes, validHash(receipt.sha256) else { throw Failure.invalid }
    }
    private func load(_ url: URL) throws -> Receipt {
        var bytes = Data()
        try RetainedMediaReader.read(url,maximumBytes:Self.maximumReceiptBytes) { bytes.append($0) }
        let receipt = try JSONDecoder().decode(Receipt.self,from:bytes)
        try validate(receipt)
        guard url.lastPathComponent == (try receiptURL(receipt.file)).lastPathComponent else { throw Failure.unsafe }
        return receipt
    }
    /// Own converter emits canonical PCM16 mono WAV. Do not advertise partial/unknown output.
    private func audioIdentity(_ url: URL) throws -> Identity {
        var hash = SHA256(), header = Data()
        let bytes = try RetainedMediaReader.read(url,maximumBytes:Self.maximumBytes) { chunk in
            if header.count < 44 { header.append(chunk.prefix(44-header.count)) }
            hash.update(data:chunk)
        }
        func u16(_ p: Int) -> UInt16 { UInt16(header[p]) | UInt16(header[p+1]) << 8 }
        func u32(_ p: Int) -> UInt32 { UInt32(u16(p)) | UInt32(u16(p+2)) << 16 }
        guard header.count == 44, header[0..<4] == Data("RIFF".utf8), header[8..<16] == Data("WAVEfmt ".utf8),
              header[36..<40] == Data("data".utf8), u32(16) == 16, u16(20) == 1, u16(22) == 1,
              u16(32) == 2, u16(34) == 16, (8000...192000).contains(u32(24)),
              u32(28) == u32(24)*2, Int64(u32(4))+8 == bytes, Int64(u32(40))+44 == bytes,
              u32(40) > 0, u32(40)%2 == 0,
              Double(u32(40))/Double(u32(28)) <= 7200 else { throw Failure.invalid }
        return Identity(bytes:bytes,sha256:hash.finalize().map { String(format:"%02x",$0) }.joined())
    }
    func publish(output: URL, context: Context) throws -> Receipt {
        try Task.checkCancellation(); try directory(root); try validate(context)
        guard output.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { throw Failure.unsafe }
        guard try list().receipts.count < 200 else { throw Failure.bounds }
        let id = try ownedID(output.lastPathComponent)
        let target = try receiptURL(output.lastPathComponent)
        let digest = try audioIdentity(output)
        let receipt = Receipt(schemaVersion:1,id:id,file:output.lastPathComponent,createdAt:context.completedAt,
            elapsedSeconds:context.completedAt.timeIntervalSince(context.startedAt),bytes:digest.bytes,sha256:digest.sha256,context:context)
        try validate(receipt)
        let data = try JSONEncoder().encode(receipt)
        guard data.count <= Self.maximumReceiptBytes else { throw Failure.bounds }
        let temporary = root.appendingPathComponent(".rvc-history-" + UUID().uuidString + ".tmp")
        try data.write(to:temporary,options:.withoutOverwriting)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let handle = try FileHandle(forWritingTo:temporary)
        do { try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
        try Task.checkCancellation()
        // Atomic same-filesystem publication, failing if any destination already exists.
        // No cancellation checks/throwing work after this irreversible commit boundary.
        guard link(temporary.path,target.path) == 0 else { throw Failure.exists }
        return receipt
    }
    func list() throws -> Listing {
        try Task.checkCancellation(); try directory(root)
        var failed = false
        guard let entries = FileManager.default.enumerator(at:root,includingPropertiesForKeys:nil,
                options:[.skipsSubdirectoryDescendants],errorHandler:{ _,_ in failed=true; return false }) else { throw Failure.unsafe }
        var count=0, rejected=0, receipts:[Receipt]=[], wavs=Set<String>(), indexed=Set<String>()
        while let url = entries.nextObject() as? URL {
            try Task.checkCancellation(); count += 1
            guard count <= 1024 else { throw Failure.bounds }
            let file = url.lastPathComponent
            if file.hasSuffix(".wav"), (try? ownedID(file)) != nil {
                if (try? regularSize(url,maximum:Self.maximumBytes)) != nil { wavs.insert(file) }
                else { rejected += 1 }
            } else if file.hasPrefix("RVC-preview-"), file.hasSuffix(".json") {
                do {
                    let receipt = try load(url)
                    guard try regularSize(root.appendingPathComponent(receipt.file),maximum:Self.maximumBytes) == receipt.bytes else { throw Failure.changed }
                    receipts.append(receipt); indexed.insert(receipt.file)
                } catch is CancellationError { throw CancellationError() }
                catch { rejected += 1 }
                guard receipts.count <= 200 else { throw Failure.bounds }
            }
        }
        guard !failed else { throw Failure.unsafe }
        return Listing(receipts:receipts.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt },rejected:rejected,unindexed:wavs.subtracting(indexed).count)
    }
    func verify(_ receipt: Receipt) throws -> URL {
        try Task.checkCancellation(); try directory(root); try validate(receipt)
        guard try load(receiptURL(receipt.file)) == receipt else { throw Failure.changed }
        let url = root.appendingPathComponent(receipt.file)
        let identity = try audioIdentity(url)
        guard identity.bytes == receipt.bytes, identity.sha256 == receipt.sha256 else { throw Failure.changed }
        return url
    }
    /// Actions receive an immutable private copy, not a stale URL verified during listing.
    func snapshot(_ receipt: Receipt, cache: URL) throws -> URL {
        let source = try verify(receipt)
        try directory(cache)
        let directory = cache.appendingPathComponent("rvc-action-"+receipt.id.uuidString.lowercased()+"-"+receipt.sha256,isDirectory:true)
        let output = directory.appendingPathComponent(receipt.file)
        // A usable selected copy must not depend on unrelated cache corruption/budgets.
        var info=stat()
        if lstat(directory.path,&info)==0 {
            try self.directory(directory)
            var failed=false
            guard let children=FileManager.default.enumerator(at:directory,includingPropertiesForKeys:nil,options:[.skipsSubdirectoryDescendants],errorHandler:{_,_ in failed=true;return false}) else {throw Failure.unsafe}
            var count=0
            while let child=children.nextObject() as? URL {
                try Task.checkCancellation();count += 1
                guard count==1,child.lastPathComponent==receipt.file else {throw Failure.unsafe}
            }
            guard !failed,count==1 else {throw Failure.unsafe}
            let identity=try audioIdentity(output)
            guard identity.bytes==receipt.bytes,identity.sha256==receipt.sha256,
                  try load(receiptURL(receipt.file))==receipt else {throw Failure.changed}
            try Task.checkCancellation()
            return output
        }
        guard errno==ENOENT else {throw Failure.unsafe}
        // Retain and account for interrupted staging; empty/partial attempts are not
        // completed copies. Scan only one level, reject links, and never adopt their bytes.
        var scanFailed=false
        guard let cached=FileManager.default.enumerator(at:cache,includingPropertiesForKeys:nil,options:[.skipsSubdirectoryDescendants],errorHandler:{_,_ in scanFailed=true;return false}) else {throw Failure.unsafe}
        var entries=0,copies=0,stagingCount=0,total:Int64=0
        while let entry=cached.nextObject() as? URL {
            try Task.checkCancellation();entries += 1
            guard entries<=1024 else {throw Failure.bounds}
            let staging=entry.lastPathComponent.hasPrefix(".rvc-action-staging-")
            if staging || entry.lastPathComponent.hasPrefix("rvc-action-") {
                if staging {stagingCount += 1;guard stagingCount<16 else {throw Failure.bounds}}
                else {copies += 1;guard copies<200 else {throw Failure.bounds}}
                try self.directory(entry)
                guard let children=FileManager.default.enumerator(at:entry,includingPropertiesForKeys:nil,options:[.skipsSubdirectoryDescendants],errorHandler:{_,_ in scanFailed=true;return false}) else {throw Failure.unsafe}
                var count=0
                while let child=children.nextObject() as? URL {
                    try Task.checkCancellation();count += 1;guard count==1 else {throw Failure.unsafe}
                    _ = try ownedID(child.lastPathComponent)
                    if staging {
                        var partial=stat()
                        guard lstat(child.path,&partial)==0,partial.st_mode & mode_t(S_IFMT)==mode_t(S_IFREG),partial.st_size>=0,partial.st_size<=Self.maximumBytes else {throw Failure.unsafe}
                        total += Int64(partial.st_size)
                    } else {total += try regularSize(child,maximum:Self.maximumBytes)}
                    guard total<=1_600_000_000 else {throw Failure.bounds}
                }
                guard staging || count==1 else {throw Failure.unsafe}
            }
        }
        guard !scanFailed else {throw Failure.unsafe}
        guard total+receipt.bytes<=1_600_000_000 else {throw Failure.bounds}
        let space=try FileManager.default.attributesOfFileSystem(forPath:cache.path)
        guard let free=space[.systemFreeSize] as? NSNumber,free.int64Value>receipt.bytes+64_000_000 else {throw Failure.bounds}
        let staging=cache.appendingPathComponent(".rvc-action-staging-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        var complete=false
        defer {if !complete {try? FileManager.default.removeItem(at:staging)}}
        let stagedOutput=staging.appendingPathComponent(receipt.file)
        try Data().write(to:stagedOutput,options:.withoutOverwriting)
        let handle=try FileHandle(forWritingTo:stagedOutput)
        var hash=SHA256()
        do {
            let bytes=try RetainedMediaReader.read(source,maximumBytes:Self.maximumBytes) {chunk in
                hash.update(data:chunk);try handle.write(contentsOf:chunk)
            }
            let digest=hash.finalize().map {String(format:"%02x",$0)}.joined()
            guard bytes==receipt.bytes,digest==receipt.sha256 else {throw Failure.changed}
            try handle.synchronize();try handle.close()
            guard try load(receiptURL(receipt.file))==receipt else {throw Failure.changed}
            try Task.checkCancellation()
#if canImport(Darwin)
            // Same-filesystem atomic directory publication; even an empty conflicting
            // destination must not be overwritten. No throwing work after promotion.
            guard renamex_np(staging.path,directory.path,UInt32(RENAME_EXCL))==0 else {throw Failure.exists}
#else
            // This feature ships on Apple platforms. Never substitute racy check+rename.
            throw Failure.unsafe
#endif
            complete=true
            return output
        } catch {try? handle.close();throw error}
    }
}
#endif
