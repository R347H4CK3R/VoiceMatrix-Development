import AVFoundation
import CoreML
import Foundation
import XCTest

@testable import FluidAudio

final class OriginalNemo231AdapterTests: XCTestCase {
    func testLocalNativeOptInRejectsOtherVersionsOrPrecisionsBeforeFileLoading() {
        let missing = URL(fileURLWithPath: "/nonexistent/original-nemo-frontend-not-a-model", isDirectory: true)
        for (version, precision) in [(AsrModelVersion.v2, ParakeetEncoderPrecision.int8V2),
                                     (.v3, .int8), (.tdtCtc110m, .int8V2)] {
            XCTAssertThrowsError(try AsrModels.loadLocal(
                from: missing, version: version, encoderPrecision: precision, localFrontend: .originalNemo231
            )) { error in
                guard let known = error as? AsrModelsError, case .loadingFailed(let details) = known else {
                    return XCTFail("Expected explicit native frontend eligibility rejection: \(error)")
                }
                XCTAssertTrue(details.contains("local v3 Encoder_v2"))
            }
        }
    }

    func testOriginalFrontendAdapterWithClearedActualSpeechFixture() throws {
        guard let location = ProcessInfo.processInfo.environment["ASR_ORIGINAL_FRONTEND_BUFFERS"] else {
            throw XCTSkip("Set ASR_ORIGINAL_FRONTEND_BUFFERS to the two verified native frontend files")
        }
        let root = URL(fileURLWithPath: location, isDirectory: true)
        let frontend = try Parakeet231Frontend(
            windowLE: Data(contentsOf: root.appendingPathComponent("window.f32le")),
            filterbankLE: Data(contentsOf: root.appendingPathComponent("filterbank.f32le")))
        let recording = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/01-validation-request-21.4s", withExtension: "wav")
                ?? Bundle.module.url(forResource: "01-validation-request-21.4s", withExtension: "wav"))
        let input = try AVAudioFile(forReading: recording)
        XCTAssertEqual(input.processingFormat.sampleRate, 16000)
        XCTAssertEqual(input.processingFormat.channelCount, 1)
        let valid = 80_000
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: input.processingFormat, frameCapacity: AVAudioFrameCount(valid)))
        try input.read(into: pcm, frameCount: AVAudioFrameCount(valid))
        XCTAssertEqual(Int(pcm.frameLength), valid)
        let samples = try XCTUnwrap(pcm.floatChannelData?[0])
        var padded = Array(UnsafeBufferPointer(start: samples, count: Int(pcm.frameLength)))
        padded += Array(repeating: 0, count: ASRConstants.maxModelSamples - padded.count)
        let provider = try AsrManager.nativePreprocessorOutput(frontend, audio: padded, validSamples: valid)
        XCTAssertEqual(provider.featureNames, ["mel", "mel_length"])
        let mel = try XCTUnwrap(provider.featureValue(for: "mel")?.multiArrayValue)
        let length = try XCTUnwrap(provider.featureValue(for: "mel_length")?.multiArrayValue)
        XCTAssertEqual(mel.shape, [1, 128, 1501])
        XCTAssertEqual(mel.dataType, .float32)
        XCTAssertEqual(length.shape, [1])
        XCTAssertEqual(length.dataType, .int32)
        let count = valid / 160 + 1
        XCTAssertEqual(length[0].intValue, count)
        let flat = mel.dataPointer.assumingMemoryBound(to: Float.self)
        var sawSpeechFeatures = false
        for bin in 0..<128 {
            for frame in 0..<1501 {
                let value = flat[bin * 1501 + frame]
                XCTAssertTrue(value.isFinite)
                if frame >= count {
                    XCTAssertEqual(value.bitPattern, 0)
                } else if abs(value) > 0.01 {
                    sawSpeechFeatures = true
                }
            }
        }
        XCTAssertTrue(sawSpeechFeatures)
        XCTAssertThrowsError(try AsrManager.nativePreprocessorOutput(
            frontend, audio: Array(padded.prefix(239_999)), validSamples: valid))
    }
}
