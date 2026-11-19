import CryptoKit
import Foundation
import XCTest
@testable import VoiceMatrix

@MainActor
final class LocalMatroskaWorkflowMediaTests: XCTestCase {
    private struct Job {
        let directory: URL
        let original: LocalMediaAcquisition.Result
        let originalURL: URL
        let id = UUID()
        let attempt = UUID()
    }

    private func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixture(in directory: URL) throws -> Job {
        let bundle = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(bundle.url(forResource: "strict-mkv-licensed", withExtension: "mp4"))
        let manifest = try XCTUnwrap(bundle.url(forResource: "strict-mkv-fixture", withExtension: "json"))
        let receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        let data = try Data(contentsOf: fixture)
        let sha = hash(data)
        XCTAssertEqual(sha, receipt["mp4SHA256"] as? String)
        XCTAssertEqual(receipt["sourceSHA256"] as? String, "1c7709259d871c7a36fe1f994f6f1bce0a3424c6f009002eb3defcd3f1a97040")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let original = directory.appendingPathComponent("original.mp4")
        try data.write(to: original, options: .withoutOverwriting)
        return Job(directory: directory, original: .init(file: original.lastPathComponent, sha256: sha,
                                                          bytes: Int64(data.count)), originalURL: original)
    }

    private func run(_ job: Job, stop: Bool = false) async throws -> LocalMatroskaWorkflow.Output {
        try await LocalMatroskaWorkflow.run(jobDirectory: job.directory, jobID: job.id, attemptID: job.attempt,
                                            acquisition: job.original, maximumRetainedBytes: 32_000_000) { status in
            if stop && status == "Decoding analysis media from the verified MKV." {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
    }

    private func stopAfterMKV(_ job: Job) async throws -> URL {
        let work = Task { try await run(job, stop: true) }
        do { _ = try await work.value; XCTFail("Expected cancellation after MKV commit") }
        catch is CancellationError { }
        let files = try FileManager.default.contentsOfDirectory(atPath: job.directory.path)
        let mkvs = files.filter { $0.hasSuffix(".mkv") }
        XCTAssertEqual(mkvs.count, 1)
        XCTAssertFalse(files.contains { $0.hasSuffix(".mov") })
        return job.directory.appendingPathComponent(try XCTUnwrap(mkvs.first))
    }

    func testBundledPythonResumesVerifiedMKVWithoutOriginalAndExtractsExactClip() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: root) }
        let job = try fixture(in: root.appendingPathComponent("job", isDirectory: true))
        let sentinel = root.appendingPathComponent("existing-voice.keep")
        let sentinelData = Data("existing voice unchanged".utf8)
        try sentinelData.write(to: sentinel)
        let mkv = try await stopAfterMKV(job)
        let preserved = root.appendingPathComponent("preserved-original.mp4")
        try fm.moveItem(at: job.originalURL, to: preserved)
        let output = try await run(job)
        let mov = job.directory.appendingPathComponent(output.derived.file)
        XCTAssertEqual(mkv.lastPathComponent, output.mkv.file)
        XCTAssertEqual(Set([output.acquisition.sha256, output.mkv.sha256, output.derived.sha256]).count, 3)
        XCTAssertEqual(output.timing.mkvSHA256, output.mkv.sha256)
        XCTAssertEqual(output.timing.movSHA256, output.derived.sha256)
        let clip = try await SeparationClipExtractor.extract(source: mov, start: 2, seconds: 10)
        XCTAssertEqual(clip.start, 2)
        XCTAssertEqual(clip.frames, 441_000)
        XCTAssertEqual(clip.sampleRate, 44_100)
        XCTAssertEqual(clip.samples.count, 882_000)
        XCTAssertFalse(fm.fileExists(atPath: job.originalURL.path))
        XCTAssertEqual(hash(try Data(contentsOf: preserved)), job.original.sha256)
        XCTAssertEqual(try Data(contentsOf: sentinel), sentinelData)
        let clipStore = SeparationStore(root: root.appendingPathComponent("retained-clips", isDirectory: true))
        let sourceLineage = MatroskaSourceLineage(schemaVersion: 1, jobID: job.id, attemptID: job.attempt,
                                                  acquisitionSHA256: output.acquisition.sha256, mkvSHA256: output.mkv.sha256,
                                                  derivedSHA256: output.derived.sha256)
        let committed = try await SeparationClipHandoff.prepare(
            source: .init(jobID: job.id, url: mov, sha256: output.derived.sha256, matroskaLineage: sourceLineage),
            start: 2, seconds: 10, store: clipStore)
        let committedLineage = try XCTUnwrap(SeparationClipHandoff.verifiedLineage(committed, store: clipStore))
        XCTAssertEqual(committedLineage.source, sourceLineage)
        XCTAssertEqual(committedLineage.frames, 441_000)
        XCTAssertEqual(committedLineage.actualStart, 2)

        let documents = try XCTUnwrap(fm.urls(for: .documentDirectory, in: .userDomainMask).first)
        let evidence = documents.appendingPathComponent("strict-mkv-native-evidence", isDirectory: true)
        try fm.createDirectory(at: evidence, withIntermediateDirectories: false)
        try fm.copyItem(at: mkv, to: evidence.appendingPathComponent("source.mkv"))
        try fm.copyItem(at: mov, to: evidence.appendingPathComponent("derived.mov"))
        try fm.copyItem(at: committed.url, to: evidence.appendingPathComponent("committed-clip.wav"))
        try fm.copyItem(at: committed.url.deletingLastPathComponent().appendingPathComponent("receipt.json"),
                        to: evidence.appendingPathComponent("committed-clip-receipt.json"))
        let pcm = clip.samples.withUnsafeBufferPointer { Data(buffer: $0) }
        try pcm.write(to: evidence.appendingPathComponent("clip.f32le"), options: .withoutOverwriting)
        let receipt: [String: Any] = [
            "originalSHA256": output.acquisition.sha256, "mkvSHA256": output.mkv.sha256,
            "derivedSHA256": output.derived.sha256, "clipSHA256": hash(pcm),
            "frames": clip.frames, "startSeconds": clip.start, "sampleRate": clip.sampleRate,
            "committedWAVSHA256": committed.sha256, "committedReceiptSHA256": committed.receiptSHA256,
            "jobID": job.id.uuidString, "attemptID": job.attempt.uuidString,
            "originalAbsentDuringDeriveAndExtraction": true, "sourceAndSentinelPreserved": true
        ]
        try JSONSerialization.data(withJSONObject: receipt).write(to: evidence.appendingPathComponent("result.json"))
    }

    func testCorruptCommittedMKVRejectsDespiteIntactOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let job = try fixture(in: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let mkv = try await stopAfterMKV(job)
        let journal = root.appendingPathComponent("strict-matroska-v1.json")
        let before = try Data(contentsOf: journal)
        var changed = try Data(contentsOf: mkv)
        changed[changed.startIndex + changed.count / 2] ^= 1
        try changed.write(to: mkv)
        let fileNames = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        do { _ = try await run(job); XCTFail("Corrupt MKV accepted") }
        catch let failure as LocalMediaURLPolicy.Failure {
            guard case .changed = failure else { return XCTFail("Unexpected refusal: \(failure)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted(), fileNames)
        XCTAssertEqual(try Data(contentsOf: journal), before)
        XCTAssertEqual(try Data(contentsOf: mkv), changed)
        XCTAssertEqual(hash(try Data(contentsOf: job.originalURL)), job.original.sha256)
    }
}
