import Foundation
import CryptoKit

@main struct Probe {
    struct Fixture: Decodable { let cases: [Case] }
    struct Case: Decodable { let name: String; let seconds: Double; let audioSHA256: String }
    enum Failure: Error { case failed(String) }
    static func check(_ ok: Bool, _ reason: String) throws { if !ok { throw Failure.failed(reason) } }
    static func hash(_ url: URL) throws -> String { SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
    static func main() async throws {
        let models = URL(fileURLWithPath: CommandLine.arguments[1])
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let manifest = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtures.appendingPathComponent("fixture.json")))
        try LocalSpeakerDiarization.verify(models)
        for item in manifest.cases {
            let sourceURL = fixtures.appendingPathComponent(item.name + ".wav")
            try check(try hash(sourceURL) == item.audioSHA256, "source hash")
            let store = SeparationStore(root: output.appendingPathComponent(item.name))
            let source = SeparationClipHandoff.Source(jobID: UUID(), url: sourceURL, sha256: item.audioSHA256)
            let clip = try await SeparationClipHandoff.prepare(source: source, start: 0, seconds: item.seconds, store: store)
            let reviewStore = ClipSpeakerReviewStore(clipStore: store)
            let receiptURL = clip.url.deletingLastPathComponent().appendingPathComponent("receipt.json")
            let receiptHash = try hash(receiptURL), clipHash = try hash(clip.url)
            if item.name == "below-minimum" {
                do {
                    _ = try await ClipSpeakerReviewAnalyzer.analyze(clip, store: reviewStore, bundle: models)
                    throw Failure.failed("below-minimum admitted")
                } catch ClipSpeakerReviewStore.Failure.unsupported { }
                try check(!FileManager.default.fileExists(atPath: reviewStore.root.appendingPathComponent(clip.id.uuidString + ".json").path), "unsupported published")
            } else {
                let analysis = try await ClipSpeakerReviewAnalyzer.analyze(clip, store: reviewStore, bundle: models) { print("\(item.name): \($0)") }
                try reviewStore.validate(analysis, for: clip)
                let result = try reviewStore.publish(analysis, for: clip)
                try check(analysis.rawOverlap?.sourceSHA256 == clip.sha256, "raw source binding")
                let reopened = try reviewStore.load(for: clip)
                try check(reopened?.binding == result.binding, "durable binding")
                if item.name == "silence" { try check(result.groups.isEmpty, "silence invented speakers") }
                else { try check(!result.groups.isEmpty, "genuine speech not detected") }
                if item.name == "two" { try check(result.groups.count >= 2, "two-speaker clip did not recover two groups") }
                if item.name == "overlap" { try check(result.hasOverlap, "overlap clip not flagged") }
                if let first = result.groups.first {
                    _ = try reviewStore.saveAlias("Local review label", speaker: first.speaker, expected: result, for: clip)
                    let labeled = try reviewStore.load(for: clip)
                    try check(labeled?.alias(for: first.speaker) == "Local review label", "alias reopen")
                    try check(labeled?.binding == result.binding, "alias changed evidence")
                }
                let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                try encoder.encode(analysis).write(to: output.appendingPathComponent(item.name + "-analysis.json"), options: .withoutOverwriting)
                print("PASS \(item.name): \(result.groups.count) anonymous guesses; overlap=\(result.hasOverlap)")
            }
            try check(try hash(sourceURL) == item.audioSHA256, "original source modified")
            try check(try hash(clip.url) == clipHash, "clip modified")
            try check(try hash(receiptURL) == receiptHash, "receipt modified")
        }
        print("PASS real bounded retained-clip pipeline. macOS native inference only; not physical iPhone acceptance.")
    }
}
