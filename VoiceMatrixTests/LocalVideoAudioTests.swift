import XCTest
import AVFoundation
import UIKit
@testable import VoiceMatrix

final class LocalVideoAudioTests: XCTestCase {
    @MainActor func testNativePasteTargetRejectsMultipleItemsAndDoesNotReadWhileBlocked() async {
        let host = StudioPasteButton.PasteHost(frame: CGRect(x: 0, y: 0, width: 150, height: 48))
        host.layoutIfNeeded()
        XCTAssertGreaterThanOrEqual(host.control.frame.height, 44)
        var values: [[String]] = []
        host.onPaste = { values.append($0) }
        let provider = NSItemProvider(object: "https://youtu.be/AAAAAAAAAAA" as NSString)
        host.paste(itemProviders: [provider, provider])
        XCTAssertEqual(values, [[]], "Multiple items must reach the existing rejection path, not select the first")
        host.allowsPaste = false
        host.paste(itemProviders: [provider])
        XCTAssertEqual(values, [[]])
        host.allowsPaste = true
        let delivered = expectation(description: "Explicit native item-provider paste delivered")
        host.onPaste = { values.append($0); delivered.fulfill() }
        host.paste(itemProviders: [provider])
        await fulfillment(of: [delivered], timeout: 5)
        XCTAssertEqual(values, [[], ["https://youtu.be/AAAAAAAAAAA"]])
    }

    func testRemoteURLIsNeverOpened() async {
        do { _ = try await LocalVideoAudio.extract(source: URL(string: "https://example.invalid/video.mp4")!, start: 0, seconds: 1); XCTFail("Remote source accepted") }
        catch LocalVideoAudio.Failure.localFileRequired {} catch { XCTFail("Unexpected error: \(error)") }
    }
    func testInvalidBoundsBeforeReadingFile() async {
        for seconds in [Double.nan, Double.infinity, -1, 0.49, 15.1] {
            do { _ = try await LocalVideoAudio.extract(source: URL(fileURLWithPath: "/missing.wav"), start: 0, seconds: seconds); XCTFail("Invalid bound accepted") }
            catch LocalVideoAudio.Failure.bounds {} catch { XCTFail("Unexpected error: \(error)") }
        }
    }
    private func fixture(amplitude: Float) throws -> URL {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("local-extraction-test-\(UUID()).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 88_200)!
        buffer.frameLength = 88_200
        for channel in 0..<2 { for i in 0..<88_200 { buffer.floatChannelData![channel][i] = amplitude * sin(Float(i) * 2 * .pi * 440 / 44_100) } }
        let file = try AVAudioFile(forWriting: path, settings: format.settings)
        try file.write(from: buffer)
        return path
    }
    func testLocalStereoAudioIsBoundedMonoPCMWithoutChangingSource() async throws {
        let path = try fixture(amplitude: 0.2)
        defer { try? FileManager.default.removeItem(at: path) }
        let original = try Data(contentsOf: path)
        let result = try await LocalVideoAudio.extract(source: path, start: 0.2, seconds: 1)
        XCTAssertEqual(result.seconds, 1, accuracy: 0.02)
        XCTAssertEqual(String(decoding: result.wave.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertLessThanOrEqual(result.wave.count, 720_044)
        XCTAssertGreaterThan(result.rms, 0.01)
        XCTAssertEqual(try Data(contentsOf: path), original)
    }
    func testSilenceIsNotAdmittedAsReference() async throws {
        let path = try fixture(amplitude: 0)
        defer { try? FileManager.default.removeItem(at: path) }
        do { _ = try await LocalVideoAudio.extract(source: path, start: 0, seconds: 1); XCTFail("Silence accepted") }
        catch LocalVideoAudio.Failure.unusableAudio {}
    }
}
