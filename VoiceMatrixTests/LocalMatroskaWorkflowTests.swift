import CryptoKit
import Foundation
import XCTest
@testable import VoiceMatrix

@MainActor
final class LocalMatroskaWorkflowTests: XCTestCase {
    typealias Workflow = LocalMatroskaWorkflow

    private final class Fixture {
        let directory: URL
        let job = UUID()
        let attempt = UUID()
        let original: Workflow.Media
        let mkv = Data("synthetic MKV stand-in".utf8)
        let mov = Data("synthetic MOV stand-in".utf8)
        var seen: [String] = []
        var remuxes = 0
        var derives = 0
        var cutoff = false
        var stale = false
        var duplicate = false
        var mutateBeforeSnapshot = false
        var invalidFrames = false
        var cancelDuringDecision = false
        var freeBytes: Int64 = 2_000_000_000

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            let data = Data("synthetic MP4 stand-in".utf8)
            original = .init(file: "original.mp4", sha256: Self.hash(data), bytes: Int64(data.count))
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            try data.write(to: directory.appendingPathComponent(original.file))
        }
        deinit { try? FileManager.default.removeItem(at: directory) }
        static func hash(_ data: Data) -> String {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
        @MainActor
        func run(attempt override: UUID? = nil, budget: Int64 = 500_000) async throws -> Workflow.Output {
            try await Workflow.run(jobDirectory: directory, jobID: job, attemptID: override ?? attempt,
                                   acquisition: original, maximumRetainedBytes: budget, decide: { json in
                let request = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
                let stage = try XCTUnwrap(request["stage"] as? String)
                self.seen.append(stage)
                if self.mutateBeforeSnapshot && stage == "acquisition" {
                    try Data("changed original".utf8).write(to: self.directory.appendingPathComponent(self.original.file))
                }
                if self.cancelDuringDecision { withUnsafeCurrentTask { $0?.cancel() } }
                let actions = ["acquisition": "prepare", "mkvVerified": "derive", "derivedVerified": "complete"]
                let reply = String(decoding: try JSONSerialization.data(withJSONObject: [
                    "schemaVersion": 1, "stage": stage, "jobID": self.job.uuidString.lowercased(),
                    "attemptID": (self.stale ? UUID() : self.attempt).uuidString.lowercased(),
                    "action": try XCTUnwrap(actions[stage])
                ]), as: UTF8.self)
                return self.duplicate ? "{\"action\":\"prepare\"," + String(reply.dropFirst()) : reply
            }, remux: { source, destination, _ in
                self.remuxes += 1
                XCTAssertNotEqual(source, self.directory.appendingPathComponent(self.original.file))
                XCTAssertEqual(Self.hash(try Data(contentsOf: source)), self.original.sha256)
                try self.mkv.write(to: destination, options: .withoutOverwriting)
            }, derive: { source, digest, destination, _ in
                self.derives += 1
                if self.cutoff { throw CancellationError() }
                XCTAssertEqual(source.pathExtension, "mkv")
                XCTAssertEqual(try Data(contentsOf: source), self.mkv)
                XCTAssertEqual(digest, Self.hash(self.mkv))
                try self.mov.write(to: destination, options: .withoutOverwriting)
                return .init(mkvSHA256: digest, movSHA256: Self.hash(self.mov), movBytes: Int64(self.mov.count),
                             audioPackets: 144, audioFrames: self.invalidFrames ? 147_455 : 147_456,
                             audioSampleRate: 48_000, audioChannels: 1, videoFrames: 90,
                             videoEndMilliseconds: 3000, discardFrames: 0)
            }, volumeCapacity: { _ in self.freeBytes })
        }
    }

    func testCommitThenResumeWithoutOriginalAndReplayWithoutEffects() async throws {
        let fixture = try Fixture()
        fixture.cutoff = true
        do { _ = try await fixture.run(); XCTFail("Expected interruption") } catch is CancellationError { }
        try FileManager.default.moveItem(at: fixture.directory.appendingPathComponent(fixture.original.file),
                                        to: fixture.directory.appendingPathComponent("preserved-original.backup"))
        fixture.cutoff = false
        let output = try await fixture.run()
        XCTAssertEqual(output.derived.sha256, Fixture.hash(fixture.mov))
        XCTAssertEqual(output.mkv.sha256, Fixture.hash(fixture.mkv))
        XCTAssertEqual(fixture.seen, ["acquisition", "mkvVerified", "mkvVerified", "derivedVerified"])
        _ = try await fixture.run()
        XCTAssertEqual(fixture.seen.count, 4)
        XCTAssertEqual(fixture.remuxes, 1)
        XCTAssertEqual(fixture.derives, 2)
    }

    func testCorruptMKVDoesNotRemuxEvenWithIntactMP4() async throws {
        let fixture = try Fixture()
        let output = try await fixture.run()
        let original = fixture.directory.appendingPathComponent(fixture.original.file)
        let before = try Data(contentsOf: original)
        try Data("changed".utf8).write(to: fixture.directory.appendingPathComponent(output.mkv.file))
        do { _ = try await fixture.run(); XCTFail("Corrupt MKV accepted") } catch { }
        XCTAssertEqual(fixture.remuxes, 1)
        XCTAssertEqual(fixture.derives, 1)
        XCTAssertEqual(try Data(contentsOf: original), before)
    }

    func testStalePolicyAndBudgetPreventRemux() async throws {
        let fixture = try Fixture()
        fixture.stale = true
        do { _ = try await fixture.run(); XCTFail("Stale reply accepted") }
        catch { XCTAssertEqual(error as? Workflow.Failure, .policy) }
        fixture.stale = false
        do { _ = try await fixture.run(budget: 1); XCTFail("Insufficient budget accepted") }
        catch { XCTAssertEqual(error as? Workflow.Failure, .budget) }
        XCTAssertEqual(fixture.remuxes, 0)
    }

    func testCommittedJournalRejectsDifferentAttempt() async throws {
        let fixture = try Fixture()
        _ = try await fixture.run()
        do { _ = try await fixture.run(attempt: UUID()); XCTFail("Attempt replaced") }
        catch { XCTAssertEqual(error as? Workflow.Failure, .changed) }
        XCTAssertEqual(fixture.remuxes, 1)
    }

    func testDuplicatePythonReplyAndChangedOriginalAreRejectedBeforeRemux() async throws {
        let fixture = try Fixture()
        fixture.duplicate = true
        do { _ = try await fixture.run(); XCTFail("Duplicate accepted") }
        catch { XCTAssertEqual(error as? Workflow.Failure, .policy) }
        fixture.duplicate = false
        fixture.mutateBeforeSnapshot = true
        do { _ = try await fixture.run(); XCTFail("Changed original accepted") } catch { }
        XCTAssertEqual(fixture.remuxes, 0)
    }

    func testDeriveResumeChecksDiskAndRejectsInconsistentTiming() async throws {
        let fixture = try Fixture()
        fixture.cutoff = true
        do { _ = try await fixture.run(); XCTFail("Expected interruption") } catch is CancellationError { }
        fixture.cutoff = false
        fixture.freeBytes = 800_000_000
        do { _ = try await fixture.run(); XCTFail("Missing disk reservation") }
        catch { XCTAssertEqual(error as? Workflow.Failure, .budget) }
        XCTAssertEqual(fixture.derives, 1)
        fixture.freeBytes = 2_000_000_000
        fixture.invalidFrames = true
        do { _ = try await fixture.run(); XCTFail("Bad frame equation accepted") }
        catch { XCTAssertEqual(error as? Workflow.Failure, .changed) }
        XCTAssertEqual(fixture.remuxes, 1)
    }

    func testCancelledDecisionNeverStartsRemux() async throws {
        let fixture = try Fixture()
        fixture.cancelDuringDecision = true
        let work = Task { try await fixture.run() }
        do { _ = try await work.value; XCTFail("Cancellation ignored") } catch is CancellationError { }
        XCTAssertEqual(fixture.remuxes, 0)
    }
    func testPublishedValidationPermitsOriginalAbsentAndRejectsOrphanSwap() async throws {
        let fixture = try Fixture()
        let output = try await fixture.run()
        let folder = fixture.directory
        let original = folder.appendingPathComponent(fixture.original.file)
        let backup = folder.appendingPathComponent("preserved-original.backup")
        try FileManager.default.moveItem(at: original, to: backup)
        let journal = folder.appendingPathComponent("strict-matroska-v1.json")
        let unchanged = try Data(contentsOf: journal)
        try await Workflow.validatePublished(jobDirectory: folder, jobID: fixture.job, attemptID: fixture.attempt,
                                             acquisition: output.acquisition, mkv: output.mkv, derived: output.derived)
        let orphan = Workflow.Media(file: "strict-" + UUID().uuidString.lowercased() + ".mkv",
                                    sha256: Fixture.hash(Data("orphan MKV".utf8)), bytes: 10)
        try Data("orphan MKV".utf8).write(to: folder.appendingPathComponent(orphan.file), options: .withoutOverwriting)
        try await LocalMediaAcquisition.verify(orphan, folder: folder)
        let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        do {
            try await Workflow.validatePublished(jobDirectory: folder, jobID: fixture.job, attemptID: fixture.attempt,
                                                 acquisition: output.acquisition, mkv: orphan, derived: output.derived)
            XCTFail("Independently valid orphan must not replace the journal-bound MKV")
        } catch { XCTAssertEqual(error as? Workflow.Failure, .changed) }
        XCTAssertEqual(try Data(contentsOf: journal), unchanged)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted(), before)
        XCTAssertEqual(Fixture.hash(try Data(contentsOf: backup)), fixture.original.sha256)
        XCTAssertEqual(fixture.remuxes, 1)
        XCTAssertEqual(fixture.derives, 1)
    }
}
