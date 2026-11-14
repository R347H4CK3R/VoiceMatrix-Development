import Foundation

// User labels are separate from source metadata and never certify speaker identity.
// An exact reference hash prevents a replacement voice inheriting the old label.
actor CharacterNameStore {
    enum Failure: Error { case invalid, damaged }
    private struct Record: Codable {
        let schemaVersion: Int
        let id, referenceHash: String
        let name: String?
    }
    private let root: URL
    init(root: URL) { self.root = root }
    private func file(id: String, referenceHash: String) throws -> URL {
        guard id.range(of: "^[a-z0-9_-]{1,100}$", options: .regularExpression) != nil,
              referenceHash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw Failure.invalid }
        return root.appendingPathComponent(id + "-" + referenceHash + ".json")
    }
    private func validateRoot() throws {
        guard root.isFileURL else { throw Failure.invalid }
        if FileManager.default.fileExists(atPath: root.path) {
            let values = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure.damaged }
        }
    }
    private func clean(_ name: String) throws -> String {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 80,
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw Failure.invalid }
        return value
    }
    func name(id: String, referenceHash: String) throws -> String? {
        let url = try file(id: id, referenceHash: referenceHash)
        try validateRoot()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size > 0, size <= 4096 else { throw Failure.damaged }
        let data = try Data(contentsOf: url)
        guard data.count == size else { throw Failure.damaged }
        let record = try JSONDecoder().decode(Record.self, from: data)
        guard record.schemaVersion == 1, record.id == id, record.referenceHash == referenceHash else { throw Failure.damaged }
        if let name = record.name { guard try clean(name) == name else { throw Failure.damaged } }
        return record.name
    }
    func save(id: String, referenceHash: String, name: String?) throws {
        let url = try file(id: id, referenceHash: referenceHash)
        let cleaned = try name.map(clean)
        // Do not silently overwrite a damaged record; preserve it for recovery.
        _ = try self.name(id: id, referenceHash: referenceHash)
        let data = try JSONEncoder().encode(Record(schemaVersion: 1, id: id, referenceHash: referenceHash, name: cleaned))
        guard data.count <= 4096 else { throw Failure.invalid }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try validateRoot()
        try data.write(to: url, options: .atomic)
    }
}
