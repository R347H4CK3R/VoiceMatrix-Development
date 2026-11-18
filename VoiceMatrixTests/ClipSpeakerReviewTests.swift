import XCTest
import Foundation
import CryptoKit
import AVFoundation
@testable import VoiceMatrix

final class ClipSpeakerReviewTests: XCTestCase {
    private struct Fixture {
        let clip: SeparationClipHandoff.Input
        let source: SeparationClipHandoff.Source
        let store: ClipSpeakerReviewStore
        let receipt: URL
        let sourceBytes: Data
        let clipBytes: Data
        let receiptBytes: Data
        var sidecar: URL { store.root.appendingPathComponent(clip.id.uuidString + ".json") }

        func analysis(seconds: Double = 4, hash: String? = nil,
                      counts: [Int] = [1,1,1,1],
                      segments: [LocalSpeakerPolicy.Segment] = [
                        .init(speaker: "z", start: 0, end: 2),
                        .init(speaker: "a", start: 2, end: 4)
                      ]) throws -> LocalSpeakerDiarization.Analysis {
            let revision = "df2625ac79a7ac6b65ad868fee6d80f320da4232"
            let raw = LocalOverlapPolicy.Evidence(version: 1, sourceSHA256: hash ?? clip.sha256,
                modelRevision: revision, duration: seconds, frameDuration: 1, speakerSlots: 3, counts: counts)
            let windows = try LocalSpeakerDiarization.excludingRawOverlap(
                LocalSpeakerPolicy.speakerWindows(segments, duration: seconds, candidateLimit: 6), evidence: raw)
            return .init(modelRevision: revision, seconds: seconds, segments: segments,
                speakerWindows: windows, selectionPolicyVersion: 5, rawOverlap: raw)
        }

        func assertOriginalsUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
            XCTAssertEqual(try Data(contentsOf: source.url), sourceBytes, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: clip.url), clipBytes, file: file, line: line)
            XCTAssertEqual(try Data(contentsOf: receipt), receiptBytes, file: file, line: line)
        }
    }

    private func fixture(frames: Int = 176_400, samples: [Float]? = nil) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        let clips = SeparationStore(root: root.appendingPathComponent("clips"))
        try clips.prepare()
        let id = UUID(), sourceID = UUID()
        let sourceURL = root.appendingPathComponent("retained.wav")
        let sourceBytes = Data("untouched original".utf8)
        try sourceBytes.write(to: sourceURL)
        let sourceHash = digest(sourceBytes)
        let folder = clips.root.appendingPathComponent("Clip-" + id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let wave = folder.appendingPathComponent("clip.wav")
        try SeparationStore.writeWAV(samples ?? Array(repeating: 0.03, count: frames * 2), gain: 1, to: wave)
        let clipBytes = try Data(contentsOf: wave), hash = digest(clipBytes)
        let receipt = folder.appendingPathComponent("receipt.json")
        let receiptBytes = try JSONEncoder().encode(SeparationClipHandoff.Receipt(id: id, sourceJobID: sourceID,
            sourceSHA256: sourceHash, requestedStart: 20, requestedSeconds: Double(frames)/44_100,
            actualStart: 20, frames: frames, clipSHA256: hash))
        try receiptBytes.write(to: receipt)
        return Fixture(clip: .init(id: id, url: wave, sha256: hash, receiptSHA256: digest(receiptBytes), start: 20, frames: frames),
                       source: .init(jobID: sourceID, url: sourceURL, sha256: sourceHash),
                       store: ClipSpeakerReviewStore(clipStore: clips), receipt: receipt,
                       sourceBytes: sourceBytes, clipBytes: clipBytes, receiptBytes: receiptBytes)
    }

    private func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    func testExactClipAndReviewSurviveReopenWithoutChangingSourceAndReceipt() throws {
        let f = try fixture()
        XCTAssertEqual(try f.store.preparedClips(for: f.source), [f.clip])
        XCTAssertNil(try f.store.load(for: f.clip))
        let initial = try f.store.publish(f.analysis(), for: f.clip)
        XCTAssertEqual(initial.groups.map(\.id), ["S1", "S2"])
        XCTAssertEqual(initial.groups.map(\.speaker), ["z", "a"])
        let labeled = try f.store.saveAlias("Narrator", speaker: "z", expected: initial, for: f.clip)
        let reopened = try XCTUnwrap(f.store.load(for: f.clip))
        XCTAssertEqual(labeled.binding, initial.binding)
        XCTAssertEqual(reopened.binding, initial.binding)
        XCTAssertEqual(reopened.alias(for: "z"), "Narrator")
        XCTAssertNil(reopened.alias(for: "a"))
        XCTAssertNil(try f.store.saveAlias(nil, speaker: "z", expected: reopened, for: f.clip).alias(for: "z"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: f.store.root.path), [f.sidecar.lastPathComponent])
        try f.assertOriginalsUnchanged()
    }

    func testRejectsStaleAliasesUnknownSpeakerAndControlCharactersWithoutReplacingValidSidecar() throws {
        let f = try fixture()
        let record = try f.store.publish(f.analysis(), for: f.clip)
        _ = try f.store.saveAlias("Original", speaker: "z", expected: record, for: f.clip)
        let before = try Data(contentsOf: f.sidecar)
        XCTAssertThrowsError(try f.store.saveAlias("Stale", speaker: "z", expected: record, for: f.clip))
        let fresh = try XCTUnwrap(f.store.load(for: f.clip))
        for invalid in ["", " ", "line\nbreak", "a\u{0000}b", "a\u{2028}b", String(repeating: "x", count: 81)] {
            XCTAssertThrowsError(try f.store.saveAlias(invalid, speaker: "z", expected: fresh, for: f.clip))
        }
        XCTAssertThrowsError(try f.store.saveAlias("Unknown", speaker: "other", expected: fresh, for: f.clip))
        XCTAssertThrowsError(try f.store.publish(f.analysis(), for: f.clip))
        XCTAssertEqual(try Data(contentsOf: f.sidecar), before)
        try f.assertOriginalsUnchanged()
    }

    func testRejectsShortLongMismatchedAndLegacyEvidenceBeforePublication() throws {
        let short = try fixture(frames: 132_299), f = try fixture()
        XCTAssertThrowsError(try short.store.publish(short.analysis(), for: short.clip))
        XCTAssertFalse(FileManager.default.fileExists(atPath: short.sidecar.path))
        let exact = try fixture(frames: 132_300), long = try fixture(frames: 441_001), upper = try fixture(frames: 441_000)
        XCTAssertNoThrow(try exact.store.publish(exact.analysis(seconds: 3, counts: [0,0,0], segments: []), for: exact.clip))
        XCTAssertThrowsError(try long.store.publish(long.analysis(seconds: 10, counts: Array(repeating: 0, count: 10), segments: []), for: long.clip))
        XCTAssertNoThrow(try upper.store.publish(upper.analysis(seconds: 10, counts: Array(repeating: 0, count: 10), segments: []), for: upper.clip))
        XCTAssertThrowsError(try f.store.publish(f.analysis(hash: String(repeating: "1",count: 64)), for: f.clip))
        var legacy = try f.analysis()
        legacy.selectionPolicyVersion = 4
        legacy.rawOverlap = nil
        XCTAssertThrowsError(try f.store.publish(legacy, for: f.clip))
        XCTAssertThrowsError(try f.store.publish(f.analysis(seconds: 5, counts: [1,1,1,1,1]), for: f.clip))
        XCTAssertNil(try f.store.load(for: f.clip))
        try f.assertOriginalsUnchanged()
    }

    func testTamperedBoundAliasAnalysisReceiptAndMediaNeverReopenAsValid() throws {
        let f = try fixture()
        let initial = try f.store.publish(f.analysis(), for: f.clip)
        _ = try f.store.saveAlias("Voice A", speaker: "z", expected: initial, for: f.clip)
        let original = try Data(contentsOf: f.sidecar)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var aliases = try XCTUnwrap(json["aliases"] as? [[String: Any]])
        var binding = try XCTUnwrap(aliases[0]["binding"] as? [String: Any])
        binding["analysisSHA256"] = String(repeating: "0", count: 64)
        aliases[0]["binding"] = binding
        json["aliases"] = aliases
        let tampered = try JSONSerialization.data(withJSONObject: json)
        try tampered.write(to: f.sidecar)
        XCTAssertThrowsError(try f.store.load(for: f.clip))
        XCTAssertEqual(try Data(contentsOf: f.sidecar), tampered)
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var analysis = try XCTUnwrap(json["analysis"] as? [String: Any])
        var segments = try XCTUnwrap(analysis["segments"] as? [[String: Any]])
        segments[0]["start"] = 0.25 // Still a valid turn under policy, but not the same analysis.
        analysis["segments"] = segments
        json["analysis"] = analysis
        let changedAnalysis = try JSONSerialization.data(withJSONObject: json)
        try changedAnalysis.write(to: f.sidecar)
        XCTAssertThrowsError(try f.store.load(for: f.clip))
        XCTAssertEqual(try Data(contentsOf: f.sidecar), changedAnalysis)
        try original.write(to: f.sidecar)
        try (f.receiptBytes + Data(" ".utf8)).write(to: f.receipt)
        XCTAssertThrowsError(try f.store.load(for: f.clip))
        try f.receiptBytes.write(to: f.receipt)
        var damagedClip = f.clipBytes
        damagedClip[44] ^= 1
        try damagedClip.write(to: f.clip.url)
        XCTAssertThrowsError(try f.store.load(for: f.clip))
        XCTAssertEqual(try Data(contentsOf: f.clip.url), damagedClip)
        XCTAssertEqual(try Data(contentsOf: f.sidecar), original)
        XCTAssertEqual(try Data(contentsOf: f.source.url), f.sourceBytes)
    }

    func testRejectsLinkedOrOversizedSidecarAndPreservesTarget() throws {
        let f = try fixture()
        _ = try f.store.publish(f.analysis(), for: f.clip)
        let fm = FileManager.default
        let outside = f.store.root.deletingLastPathComponent().appendingPathComponent("original-sidecar.json")
        try fm.moveItem(at: f.sidecar, to: outside)
        try fm.createSymbolicLink(at: f.sidecar, withDestinationURL: outside)
        let original = try Data(contentsOf: outside)
        XCTAssertThrowsError(try f.store.load(for: f.clip))
        XCTAssertThrowsError(try f.store.publish(f.analysis(), for: f.clip))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: f.sidecar.path), outside.path)
        XCTAssertEqual(try Data(contentsOf: outside), original)
        try fm.removeItem(at: f.sidecar)
        try Data(repeating: 0, count: 300_000).write(to: f.sidecar)
        XCTAssertThrowsError(try f.store.load(for: f.clip))
        XCTAssertEqual(try Data(contentsOf: f.sidecar).count, 300_000)
        try f.assertOriginalsUnchanged()
    }

    func testSpeakerTurnsAreNotCleanReferenceClaims() throws {
        let f = try fixture()
        let overlap = try f.store.publish(f.analysis(counts: [1,2,1,1]), for: f.clip)
        XCTAssertTrue(overlap.hasOverlap)
        XCTAssertEqual(overlap.groups.count, 2)
        XCTAssertTrue(overlap.groups.allSatisfy { !$0.hasPolicyWindow })
        let quiet = try fixture()
        let noEvidence = try quiet.store.publish(quiet.analysis(counts: [0,0,0,0]), for: quiet.clip)
        XCTAssertTrue(noEvidence.groups.isEmpty)
        XCTAssertFalse(noEvidence.hasOverlap)
    }

    // Independent native file reading plus different converter buffer sizes checks
    // the actual boundary and channel balance, not just duration.
    private func referencePCM(_ url: URL, frames: Int) throws -> [Float] {
        let wav = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let filePCM = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: wav.processingFormat, frameCapacity: AVAudioFrameCount(frames)))
        try wav.read(into: filePCM)
        XCTAssertEqual(Int(filePCM.frameLength), frames)
        let channels = try XCTUnwrap(filePCM.floatChannelData)
        let mono = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false))
        let target = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 1_537))
        let output = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 1_024))
        let converter = try XCTUnwrap(AVAudioConverter(from: mono, to: target))
        converter.primeMethod = .normal
        var offset = 0, result: [Float] = []
        for _ in 0..<200 {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { requested, state in
                guard offset < frames else { state.pointee = .endOfStream; return nil }
                let count = min(frames - offset, Int(requested), Int(input.frameCapacity))
                guard count > 0 else { state.pointee = .noDataNow; return nil }
                let monoData = input.floatChannelData![0]
                for i in 0..<count {
                    monoData[i] = 0.5 * channels[0][offset + i] + 0.5 * channels[1][offset + i]
                }
                offset += count
                input.frameLength = AVAudioFrameCount(count)
                state.pointee = .haveData
                return input
            }
            XCTAssertNil(error)
            XCTAssertNotEqual(status, .error)
            result.append(contentsOf: UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
            if status == .endOfStream {
                XCTAssertEqual(offset, frames)
                return result
            }
        }
        XCTFail("Reference AVAudioConverter did not drain")
        return result
    }

    func testRetainedCanonicalPCMDecodesExactThreeEightAndTenSecondsWithAVAudioFileParity() throws {
        for seconds in [3, 8, 10] {
            let frames = seconds * 44_100
            var stereo: [Float] = []
            stereo.reserveCapacity(frames * 2)
            for i in 0..<frames {
                stereo.append(i + 20 >= frames ? 0.7 : Float(i % 229 - 114) / 500)
                stereo.append(i < 40 ? -0.4 : Float(i % 101 - 50) / 300)
            }
            let f = try fixture(frames: frames, samples: stereo)
            let samples = try LocalSpeakerDiarization.decodeRetainedClip(f.clip.url, frames: frames, sourceSHA256: f.clip.sha256)
            let oracle = try referencePCM(f.clip.url, frames: frames)
            XCTAssertEqual(samples.count, seconds * 16_000)
            XCTAssertEqual(oracle.count, seconds * 16_000)
            let largestDifference = zip(samples, oracle).map { abs($0.0 - $0.1) }.max() ?? .infinity
            XCTAssertLessThan(largestDifference, 1e-6)
            try f.assertOriginalsUnchanged()
        }
    }

    func testRetainedCanonicalPCMRejectsWrongSizeHashAndHeaderWithoutWriting() throws {
        let f = try fixture()
        XCTAssertThrowsError(try LocalSpeakerDiarization.decodeRetainedClip(f.clip.url, frames: 132_299, sourceSHA256: f.clip.sha256))
        XCTAssertThrowsError(try LocalSpeakerDiarization.decodeRetainedClip(f.clip.url, frames: f.clip.frames - 1, sourceSHA256: f.clip.sha256))
        XCTAssertThrowsError(try LocalSpeakerDiarization.decodeRetainedClip(f.clip.url, frames: f.clip.frames, sourceSHA256: String(repeating: "f", count: 64)))
        var invalid = f.clipBytes
        invalid[24] ^= 0x01 // Corrupt sample rate even with a matching raw digest.
        let malformed = f.clip.url.deletingLastPathComponent().appendingPathComponent("wrong-rate.wav")
        try invalid.write(to: malformed)
        XCTAssertThrowsError(try LocalSpeakerDiarization.decodeRetainedClip(malformed, frames: f.clip.frames, sourceSHA256: digest(invalid)))
        XCTAssertEqual(try Data(contentsOf: malformed), invalid)
        try f.assertOriginalsUnchanged()
    }

    @MainActor
    func testRetainedCanonicalPCMDoesNotReturnSamplesAfterCancellation() async throws {
        let f = try fixture(), gate = ModelGate()
        let clip = f.clip
        let task = Task.detached {
            await gate.pause()
            return try LocalSpeakerDiarization.decodeRetainedClip(clip.url, frames: clip.frames, sourceSHA256: clip.sha256)
        }
        let started = await waitUntil { await gate.waiting }
        XCTAssertTrue(started)
        task.cancel()
        await gate.finish()
        do {
            _ = try await task.value
            XCTFail("A cancelled decode returned audio")
        } catch is CancellationError { }
        try f.assertOriginalsUnchanged()
    }

    private actor ModelGate {
        private var continuation: CheckedContinuation<Void, Never>?
        var waiting: Bool { continuation != nil }
        func pause() async { await withCheckedContinuation { continuation = $0 } }
        func finish() {
            continuation?.resume()
            continuation = nil
        }
    }

    @MainActor
    private func waitUntil(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<200 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return false
    }

    @MainActor
    func testAuthorizationAndExclusiveLeaseAreRequiredAndOpeningDoesNotRunAnalysis() async throws {
        let f = try fixture(), gate = ModelGate(), analysis = try f.analysis()
        let audio = AudioStore(recordingRoot: f.store.root.deletingLastPathComponent().appendingPathComponent("recordings"))
        let coordinator = ClipSpeakerReviewCoordinator(store: f.store, analyze: { _,_,_ in
            await gate.pause()
            return analysis
        })
        coordinator.activate(f.clip)
        let openedWithoutAnalysis = await gate.waiting
        XCTAssertFalse(openedWithoutAnalysis)
        XCTAssertFalse(coordinator.start(f.clip, authorized: false, audio: audio, isCurrent: { true }))
        let microphone = try XCTUnwrap(audio.claimMicrophone())
        XCTAssertFalse(coordinator.start(f.clip, authorized: true, audio: audio, isCurrent: { true }))
        audio.releaseMicrophone(microphone)
        XCTAssertFalse(coordinator.start(f.clip, authorized: true, audio: audio, isCurrent: { false }))
        XCTAssertTrue(coordinator.start(f.clip, authorized: true, audio: audio, isCurrent: { true }))
        let started = await waitUntil { await gate.waiting }
        XCTAssertTrue(started)
        XCTAssertTrue(audio.processingInUse)
        XCTAssertNil(audio.claimProcessing())
        await gate.finish()
        let finished = await waitUntil { !coordinator.busy }
        XCTAssertTrue(finished)
        XCTAssertFalse(audio.processingInUse)
        XCTAssertNotNil(try f.store.load(for: f.clip))
        try f.assertOriginalsUnchanged()
    }

    @MainActor
    func testCancelNavigationOrChangedSourceDoesNotPublishEvenIfModelReturns() async throws {
        for scenario in ["cancel", "navigation", "change"] {
            let f = try fixture(), gate = ModelGate(), analysis = try f.analysis()
            let audio = AudioStore(recordingRoot: f.store.root.deletingLastPathComponent().appendingPathComponent("recordings"))
            let coordinator = ClipSpeakerReviewCoordinator(store: f.store, analyze: { _,_,_ in
                await gate.pause() // Deliberately non-cooperative while the model call is in progress.
                return analysis
            })
            coordinator.activate(f.clip)
            var isCurrent = true
            XCTAssertTrue(coordinator.start(f.clip, authorized: true, audio: audio, isCurrent: { isCurrent }))
            let started = await waitUntil { await gate.waiting }
            XCTAssertTrue(started, scenario)
            switch scenario {
            case "cancel": coordinator.cancel()
            case "navigation": coordinator.deactivate()
            default: isCurrent = false
            }
            XCTAssertTrue(audio.processingInUse, scenario)
            await gate.finish()
            let finished = await waitUntil { !coordinator.busy }
            XCTAssertTrue(finished, scenario)
            XCTAssertFalse(audio.processingInUse, scenario)
            XCTAssertNil(coordinator.result, scenario)
            XCTAssertNil(try f.store.load(for: f.clip), scenario)
            try f.assertOriginalsUnchanged()
        }
    }

}
