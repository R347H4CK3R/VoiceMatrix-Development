import Foundation
import XCTest
@testable import VoiceMatrix

@MainActor
final class StrictMatroskaJobTests: XCTestCase {
    private let url = URL(string: "https://www.youtube.com/watch?v=abcdefghijk")!

    private func newJob() -> LocalVideoStudio.Job {
        .init(id: UUID(), created: Date(), updated: Date(), stage: "Received", message: "Test")
    }

    func testLegacyAndFileJobsRoundTripWithoutOptIn() throws {
        var legacy = newJob()
        legacy.acquisitionURL = url
        legacy.sourceFile = "original.mp4"
        legacy.sourceSHA256 = String(repeating: "a", count: 64)
        let restored = try JSONDecoder().decode(LocalVideoStudio.Job.self, from: JSONEncoder().encode(legacy))
        XCTAssertNil(restored.strictMatroska)
        XCTAssertTrue(restored.validStrictMatroska)
        XCTAssertTrue(newJob().validStrictMatroska)
    }

    func testStrictJobAcceptsOnlyCompleteDerivedSourceBinding() throws {
        var job = newJob()
        job.acquisitionURL = url
        let attempt = UUID()
        job.strictMatroska = .init(schemaVersion: 1, attemptID: attempt)
        XCTAssertTrue(job.validStrictMatroska)
        let original = LocalMediaAcquisition.Result(file: "original.mp4", sha256: String(repeating: "a", count: 64), bytes: 100)
        let mkv = LocalMediaAcquisition.Result(file: "strict-00000000-0000-4000-8000-000000000001.mkv", sha256: String(repeating: "b", count: 64), bytes: 200)
        let derived = LocalMediaAcquisition.Result(file: "strict-00000000-0000-4000-8000-000000000002.mov", sha256: String(repeating: "c", count: 64), bytes: 300)
        job.strictMatroska?.original = original
        XCTAssertTrue(job.validStrictMatroska)
        job.sourceFile = original.file
        job.sourceSHA256 = original.sha256
        XCTAssertFalse(job.validStrictMatroska)
        job.strictMatroska?.mkv = mkv
        XCTAssertFalse(job.validStrictMatroska)
        job.strictMatroska?.derived = derived
        XCTAssertFalse(job.validStrictMatroska)
        job.sourceFile = derived.file
        job.sourceSHA256 = derived.sha256
        XCTAssertTrue(job.validStrictMatroska)
        let restored = try JSONDecoder().decode(LocalVideoStudio.Job.self, from: JSONEncoder().encode(job))
        XCTAssertTrue(restored.validStrictMatroska)
        XCTAssertEqual(restored.strictMatroska?.attemptID, attempt)
        job.acquisitionURL = nil
        XCTAssertFalse(job.validStrictMatroska)
    }

    func testStrictRejectsInvalidSchemaAndCachesWithoutDerivedSource() {
        var job = newJob()
        job.acquisitionURL = url
        job.strictMatroska = .init(schemaVersion: 2, attemptID: UUID())
        XCTAssertFalse(job.validStrictMatroska)
        job.strictMatroska = .init(schemaVersion: 1, attemptID: UUID())
        job.analysisSHA256 = String(repeating: "a", count: 64)
        XCTAssertFalse(job.validStrictMatroska)
    }
}
