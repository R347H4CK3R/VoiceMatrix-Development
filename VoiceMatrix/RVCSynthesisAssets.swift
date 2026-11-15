import Foundation

/// Admission is deliberately limited to the previously CPU-tested evaluation graphs.
/// A manifest cannot authorize arbitrary models by supplying its own hash.
enum RVCSynthesisAssets {
    static let verifiedSHA256 = "fadf28f77251f486c48f9b039f62306f07e02e7ffe9be5bde2f7fc33f23360cb"
    static let vctkP226SHA256 = "f7519d6f3c248f6eb2acabd11352e0abf91515a7e95662fdb23a5b1f1e009dcc"
    static let maximumBytes = 128 * 1024 * 1024
    struct Manifest: Codable {
        let schemaVersion: Int
        let profile: String
        let file: String
        let sha256: String
        let bytes: Int
    }
    static func validateManifest(_ m: Manifest) throws {
        let accepted: (String, Set<String>, Int)
        switch m.profile {
        case "rvc-v2-922-cpu": accepted = ("synthesizer.onnx", [verifiedSHA256,vctkP226SHA256], maximumBytes)
        case "hubert-147680-cpu": accepted = ("hubert.onnx", ["980f264a909ff3d85d513e924304b1c179ff5d17280dda0b011ec01cb366aa68"], 384 * 1024 * 1024)
        default: throw RVCSynthesisFailure.invalidAsset
        }
        guard m.schemaVersion == 1, m.file == accepted.0, accepted.1.contains(m.sha256),
              (1...accepted.2).contains(m.bytes) else { throw RVCSynthesisFailure.invalidAsset }
    }
    static func voiceName(_ m:Manifest) throws -> String {
        try validateManifest(m)
        guard m.profile == "rvc-v2-922-cpu" else {throw RVCSynthesisFailure.invalidAsset}
        return m.sha256 == vctkP226SHA256 ? "VCTK p226 · evaluation" : "Synthetic diagnostic voice"
    }
    static func validateRetrievalPair(_ m:Manifest,usesRetrieval:Bool,retrievalProfile:String = "diagnostic-ivf149") throws {
        _=try voiceName(m)
        guard usesRetrieval else {return}
        let matched=(m.sha256 == verifiedSHA256 && retrievalProfile == "diagnostic-ivf149") ||
            (m.sha256 == vctkP226SHA256 && retrievalProfile == "vctk-p226-ivf1161")
        guard matched else {throw RVCSynthesisFailure.incompatibleModel}
    }
    static func defaultRetrievalRate(_ m:Manifest) throws -> Float {
        _=try voiceName(m)
        return m.sha256 == vctkP226SHA256 ? 0 : 0.75
    }
    static func regularFile(_ url: URL) throws -> Int {
        guard url.isFileURL, url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent).standardizedFileURL == url.resolvingSymlinksInPath().standardizedFileURL else {
            throw RVCSynthesisFailure.invalidAsset
        }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey,.fileSizeKey])
        guard info.isRegularFile == true, let size = info.fileSize else { throw RVCSynthesisFailure.invalidAsset }
        return size
    }
    static func manifest(at root: URL) throws -> Manifest {
        let url = root.appendingPathComponent("manifest.json")
        guard try regularFile(url) <= 4096 else { throw RVCSynthesisFailure.invalidAsset }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 4097) ?? Data()
        guard data.count <= 4096 else { throw RVCSynthesisFailure.invalidAsset }
        let result = try JSONDecoder().decode(Manifest.self, from: data)
        try validateManifest(result)
        return result
    }
    /// Make a private, verified snapshot so ORT never reopens a mutable import.
    /// The iOS caller supplies a streaming CryptoKit SHA256 accumulator.
    static func snapshot(root: URL, cache: URL, profile: String = "rvc-v2-922-cpu", update: (Data) -> Void,
                         finish: () -> String) throws -> URL {
        let m = try manifest(at: root)
        guard m.profile == profile else { throw RVCSynthesisFailure.invalidAsset }
        let source = root.appendingPathComponent(m.file)
        guard try regularFile(source) == m.bytes else { throw RVCSynthesisFailure.invalidAsset }
        let fm = FileManager.default
        let folder = cache.appendingPathComponent("rvc-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var accepted = false
        defer { if !accepted { try? fm.removeItem(at: folder) } }
        let destination = folder.appendingPathComponent(m.file)
        guard fm.createFile(atPath: destination.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw RVCSynthesisFailure.invalidAsset
        }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var total = 0
        while true {
            try Task.checkCancellation()
            let data = try input.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            total += data.count
            guard total <= m.bytes else { throw RVCSynthesisFailure.invalidAsset }
            update(data)
            try output.write(contentsOf: data)
        }
        guard total == m.bytes, finish() == m.sha256 else { throw RVCSynthesisFailure.invalidAsset }
        try output.synchronize()
        accepted = true
        return destination
    }
}
