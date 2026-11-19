import Foundation
import XCTest
@testable import VoiceMatrix

final class StrictMatroskaLineageTests: XCTestCase {
    private let job = UUID()
    private let attempt = UUID()
    private let original = String(repeating: "a", count: 64)
    private let mkv = String(repeating: "b", count: 64)
    private let mov = String(repeating: "c", count: 64)
    private let wave = String(repeating: "d", count: 64)

    private func source(derived: String? = nil) -> MatroskaSourceLineage {
        .init(schemaVersion: 1, jobID: job, attemptID: attempt, acquisitionSHA256: original,
              mkvSHA256: mkv, derivedSHA256: derived ?? mov)
    }

    func testClipReceiptBindsLineageAndExactSampleIntervalWhileLegacyDecodes() throws {
        var receipt = SeparationClipHandoff.Receipt(id: UUID(), sourceJobID: job, sourceSHA256: mov,
                                                    requestedStart: 2, requestedSeconds: 10,
                                                    actualStart: 2, frames: 441_000, clipSHA256: wave)
        let legacy = try JSONDecoder().decode(SeparationClipHandoff.Receipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertNil(legacy.matroskaLineage)
        XCTAssertTrue(legacy.validMatroskaLineage)
        receipt.matroskaLineage = source()
        let restored = try JSONDecoder().decode(SeparationClipHandoff.Receipt.self, from: JSONEncoder().encode(receipt))
        XCTAssertEqual(restored.matroskaLineage, source())
        XCTAssertTrue(restored.validMatroskaLineage)
        receipt.matroskaLineage = source(derived: mkv)
        XCTAssertFalse(receipt.validMatroskaLineage)
        receipt = .init(id: UUID(), sourceJobID: job, sourceSHA256: mov, requestedStart: 2,
                        requestedSeconds: 10, actualStart: 2, frames: 440_900, clipSHA256: wave, matroskaLineage: source())
        XCTAssertFalse(receipt.validMatroskaLineage)
    }

    func testReferenceProvenanceRoundTripAndInvalidTimeOrHashRejected() throws {
        var profile = CharacterReference(id: "test", name: "Unidentified", source: "Test fixture",
                                         permission: "Synthetic", referenceText: "Test reference text",
                                         schemaVersion: 1, kind: "f5-reference", engine: "F5TTS_v1_Base",
                                         referenceFile: "reference.wav", referenceSHA256: wave, trainedModel: false,
                                         categories: ["Local"], referenceBytes: 480_044, seconds: 10)
        let legacy = try JSONDecoder().decode(CharacterReference.self, from: JSONEncoder().encode(profile))
        XCTAssertNil(legacy.matroskaReference)
        XCTAssertTrue(legacy.validMatroskaReference)
        profile.matroskaReference = .init(source: source(), requestedStartSeconds: 2, requestedDurationSeconds: 10,
                                         retainedFrames: 240_000, sampleRate: 24_000, referenceSHA256: wave)
        let restored = try JSONDecoder().decode(CharacterReference.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(restored.matroskaReference, profile.matroskaReference)
        XCTAssertTrue(restored.validMatroskaReference)
        profile.matroskaReference = .init(source: source(), requestedStartSeconds: 1799, requestedDurationSeconds: 10,
                                         retainedFrames: 240_000, sampleRate: 24_000, referenceSHA256: wave)
        XCTAssertFalse(profile.validMatroskaReference)
        profile.matroskaReference = .init(source: source(), requestedStartSeconds: 2, requestedDurationSeconds: 10,
                                         retainedFrames: 240_000, sampleRate: 24_000, referenceSHA256: mov)
        XCTAssertFalse(profile.validMatroskaReference)
    }

    func testSeparatedVocalsReceiptAndReferenceKeepClipHashAndAbsoluteTime() throws {
        let clip = MatroskaClipLineage(source: source(), clipID: UUID(), clipReceiptSHA256: original,
                                       clipSHA256: wave, requestedStart: 20, requestedSeconds: 4,
                                       actualStart: 20, frames: 176_400)
        let vocals = String(repeating: "e", count: 64)
        let reference = String(repeating: "f", count: 64)
        let provenance = MatroskaSeparatedLineage(clip: clip, vocalsSHA256: vocals)
        XCTAssertTrue(clip.valid(inputSHA256: wave, frames: 176_400))
        XCTAssertFalse(clip.valid(inputSHA256: reference, frames: 176_400))
        XCTAssertFalse(clip.valid(inputSHA256: wave, frames: 176_399))
        XCTAssertTrue(provenance.valid(sourceSHA256: vocals))
        XCTAssertFalse(provenance.valid(sourceSHA256: reference))
        var value = MatroskaReferenceLineage(source: source(), requestedStartSeconds: 21,
                                             requestedDurationSeconds: 3, retainedFrames: 72_000,
                                             sampleRate: 24_000, referenceSHA256: reference,
                                             separatedClip: clip, vocalsSHA256: vocals)
        let restored = try JSONDecoder().decode(MatroskaReferenceLineage.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(restored, value)
        XCTAssertTrue(restored.valid(seconds: 3, sha256: reference))
        value.vocalsSHA256 = nil
        XCTAssertFalse(value.valid(seconds: 3, sha256: reference))
        let escaped = MatroskaReferenceLineage(source: source(), requestedStartSeconds: 21.01,
                                               requestedDurationSeconds: 3, retainedFrames: 72_000,
                                               sampleRate: 24_000, referenceSHA256: reference,
                                               separatedClip: clip, vocalsSHA256: vocals)
        XCTAssertFalse(escaped.valid(seconds: 3, sha256: reference))
    }

}
