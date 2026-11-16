import XCTest
import AVFoundation
@testable import VoiceMatrix

@MainActor final class ReferenceLeadingContextTests: XCTestCase {
    private func fixture(_ root: URL, seconds: Double = 1, channels: AVAudioChannelCount = 1) throws -> URL {
        let url = root.appendingPathComponent(UUID().uuidString + ".wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: channels)!
        let frames = AVAudioFrameCount(seconds * 24000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for index in 0..<Int(frames) { buffer.floatChannelData![channel][index] = Float(index % 101) / 1000 }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
    func testReferenceContextRetainsEverySampleAndDoesNotWriteSource() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try fixture(root); let before = try Data(contentsOf: url)
        let padded = try OnDeviceTranscription.referenceLeadingBuffer(url)
        XCTAssertEqual(padded.frameLength, 30000)
        let samples = padded.floatChannelData![0]
        for i in 0..<6000 { XCTAssertEqual(samples[i], 0) }
        for i in 0..<24000 { XCTAssertEqual(samples[i + 6000], Float(i % 101) / 1000) }
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
    func testReferenceContextRejectsStereoOversizeAndLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(try OnDeviceTranscription.referenceLeadingBuffer(fixture(root, channels: 2)))
        XCTAssertThrowsError(try OnDeviceTranscription.referenceLeadingBuffer(fixture(root, seconds: 30)))
        let target = try fixture(root), link = root.appendingPathComponent("linked.wav")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        XCTAssertThrowsError(try OnDeviceTranscription.referenceLeadingBuffer(link))
    }
    func testCancelledReferenceBufferNeverAllocatesOrReads() async throws {
        let cancelled = Task.detached { () async throws -> Bool in
            while !Task.isCancelled { await Task.yield() }
            do { _ = try OnDeviceTranscription.referenceLeadingBuffer(URL(fileURLWithPath: "/no-such-reference.wav")); return false }
            catch is CancellationError { return true }
        }
        cancelled.cancel()
        let observedCancellation = try await cancelled.value
        XCTAssertTrue(observedCancellation)
    }
    func testLegacyReceiptWithoutReferenceContextStillDecodes() throws {
        let json = #"{"inputSHA256":"a","transcriptSHA256":"b","tokenCount":3,"meanTokenConfidence":0.9}"#
        let evidence = try JSONDecoder().decode(OnDeviceTranscription.Evidence.self, from: Data(json.utf8))
        XCTAssertNil(evidence.referenceLeadingSeconds)
        XCTAssertNil(evidence.recoveryTailSeconds)
    }
}
