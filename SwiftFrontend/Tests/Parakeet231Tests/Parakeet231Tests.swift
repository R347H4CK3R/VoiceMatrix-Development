import Foundation
import XCTest
@testable import Parakeet231

final class Parakeet231Tests: XCTestCase {
    private func bytes(_ values: [Float]) -> Data {
        var data = Data(capacity: values.count * 4)
        for x in values {
            let bits = x.bitPattern
            for shift in stride(from: 0, to: 32, by: 8) {
                data.append(UInt8(truncatingIfNeeded: bits >> shift))
            }
        }
        return data
    }

    private func synthetic(windowTap: Int = 200) throws -> Parakeet231Frontend {
        var window = [Float](repeating: 0, count: 400); window[windowTap] = 1
        var fb = [Float](repeating: 0, count: 128 * 257); fb[0] = 1
        return try Parakeet231Frontend(analyticWindowLE: bytes(window), analyticFilterbankLE: bytes(fb))
    }

    func testAnalyticReflectLeftEdgeAndPreemphasis() throws {
        // Window tap 199 lands at center-1. At frame zero reflect(-1)=1.
        let f = try synthetic(windowTap: 199)
        var a = [Float](repeating: 0, count: 320)
        a[0] = 1; a[1] = 2; a[158] = 2; a[159] = 4; a[318] = 1; a[319] = 3
        let result = try f.features(a, validSamples: 320)
        XCTAssertEqual(result.frames, 3)
        XCTAssertEqual(result.validFrames, 3)
        let sampleValues = [2.0 - 0.97, 4.0 - 0.97 * 2, 3.0 - 0.97]
        let y = sampleValues.map { log($0 * $0 + 1.0 / 16_777_216.0) }
        let mean = y.reduce(0, +) / 3
        let sigma = sqrt(y.reduce(0) { $0 + pow($1 - mean, 2) } / 2) + 0.00001
        for i in y.indices {
            XCTAssertEqual(result.mel[i], Float((y[i] - mean) / sigma), accuracy: 1e-6)
        }
        XCTAssertTrue(result.mel.dropFirst(3).allSatisfy { $0.bitPattern == 0 })
    }

    func testAnalyticRightReflectAtExactHop() throws {
        let f = try synthetic()
        var a = [Float](repeating: 0, count: 320)
        a[0] = 1; a[160] = 1; a[318] = 2
        let result = try f.features(a, validSamples: 320)
        // Last centered frame samples index 320, which reflects to 318, not 319.
        XCTAssertEqual(result.mel[0], result.mel[1])
        XCTAssertEqual(result.mel[2], Float(2 / sqrt(3.0)), accuracy: 2e-5)
    }

    func testPaddedValidBoundaryKeepsWholeAudioPreemphasis() throws {
        let f = try synthetic(windowTap: 201)
        var a = [Float](repeating: 0, count: 320)
        a[1] = 1; a[160] = 3; a[161] = 2
        let withTail = try f.features(a, validSamples: 160)
        a[160] = 0; a[161] = 0
        let withoutTail = try f.features(a, validSamples: 160)
        XCTAssertEqual(withTail.validFrames, 2)
        XCTAssertEqual(withTail.frames, 3)
        XCTAssertGreaterThan(withTail.mel[0], 0)
        XCTAssertGreaterThan(withoutTail.mel[0], 0)
        XCTAssertNotEqual(withTail.mel[1], 0)
        XCTAssertTrue((0..<128).allSatisfy { withTail.mel[$0 * 3 + 2].bitPattern == 0 })
        // Retaining a different tail can flip the two valid frames' ordering.
        a[161] = 3
        let flipped = try f.features(a, validSamples: 160)
        XCTAssertGreaterThan(flipped.mel[1], 0)
        XCTAssertLessThan(withTail.mel[1], 0)
    }

    func testRefuseUnsupportedDomainAndNonfiniteInputs() throws {
        let f = try synthetic()
        for count in 0...256 {
            XCTAssertThrowsError(try f.features([Float](repeating: 0, count: count), validSamples: count)) {
                XCTAssertEqual($0 as? Parakeet231Error, .unsupportedAudioLength)
            }
        }
        let physical257 = [Float](repeating: 0, count: 257)
        for valid in -1...159 {
            XCTAssertThrowsError(try f.features(physical257, validSamples: valid)) {
                XCTAssertEqual($0 as? Parakeet231Error, .unsupportedValidSamples)
            }
        }
        XCTAssertThrowsError(try f.features(physical257, validSamples: 258)) {
            XCTAssertEqual($0 as? Parakeet231Error, .unsupportedValidSamples)
        }
        XCTAssertThrowsError(try f.features([Float](repeating: 0, count: 240_001), validSamples: 240_001)) {
            XCTAssertEqual($0 as? Parakeet231Error, .unsupportedAudioLength)
        }
        var a = [Float](repeating: 0, count: 257)
        a[255] = .nan
        XCTAssertThrowsError(try f.features(a, validSamples: 160))
        XCTAssertThrowsError(try Parakeet231Frontend(windowLE: Data(), filterbankLE: Data()))
        XCTAssertThrowsError(try Parakeet231Frontend(
            analyticWindowLE: bytes([Float](repeating: .nan, count: 400)),
            analyticFilterbankLE: bytes([Float](repeating: 0, count: 128 * 257))))
        XCTAssertThrowsError(try Parakeet231Frontend(
            analyticWindowLE: bytes([Float](repeating: 0, count: 400)),
            analyticFilterbankLE: bytes([Float](repeating: -1, count: 128 * 257))))
        XCTAssertThrowsError(try Parakeet231Frontend(
            windowLE: bytes([Float](repeating: 0, count: 400)),
            filterbankLE: bytes([Float](repeating: 0, count: 128 * 257)))) {
                XCTAssertEqual($0 as? Parakeet231Error, .originalBufferDigestMismatch)
        }
    }

    private struct Fixture: Decodable {
        let name: String
        let samples: Int
        let validSamples: Int
        let frames: Int
        let validFrames: Int
        let audioSHA256: String
        let melSHA256: String
    }

    func testIndependentOriginalBufferFixtures() throws {
        let path = try XCTUnwrap(ProcessInfo.processInfo.environment["ASR_SWIFT_FIXTURES"],
            "Set ASR_SWIFT_FIXTURES to the pinned input/output fixture directory. Never skip this parity test.")
        let root = URL(fileURLWithPath: path, isDirectory: true)
        func load(_ name: String) throws -> Data {
            try Data(contentsOf: root.appendingPathComponent(name))
        }
        let rows = try JSONDecoder().decode([Fixture].self, from: load("fixtures.json"))
        XCTAssertGreaterThanOrEqual(rows.count, 36)
        XCTAssertTrue(rows.contains { $0.samples == 240_000 })
        XCTAssertTrue(rows.contains { $0.samples > $0.validSamples })
        let bufferRoot = ProcessInfo.processInfo.environment["ASR_SWIFT_BUFFERS"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? root
        let f = try Parakeet231Frontend(
            windowLE: Data(contentsOf: bufferRoot.appendingPathComponent("window.f32le")),
            filterbankLE: Data(contentsOf: bufferRoot.appendingPathComponent("filterbank.f32le")))
        let names = Set(rows.map { $0.name })
        XCTAssertEqual(names.count, rows.count)
        XCTAssertTrue(names.contains("nonzero-tail-valid-160"))
        XCTAssertTrue(names.contains("nonzero-tail-valid-16000"))
        for row in rows {
            guard row.name.range(of: #"^[a-zA-Z0-9_-]+$"#, options: .regularExpression) != nil,
                  (257...240_000).contains(row.samples),
                  (160...row.samples).contains(row.validSamples),
                  row.frames == row.samples / 160 + 1, row.validFrames == row.validSamples / 160 + 1 else {
                XCTFail("Malformed fixture metadata: \(row.name)")
                continue
            }
            let audioBytes = try load(row.name + ".audio.f32le")
            let melBytes = try load(row.name + ".mel.f32le")
            XCTAssertEqual(Parakeet231Frontend.sha256(audioBytes), row.audioSHA256, row.name)
            XCTAssertEqual(Parakeet231Frontend.sha256(melBytes), row.melSHA256, row.name)
            let audio = try Parakeet231Frontend.readFloat32LE(audioBytes, count: row.samples)
            let expected = try Parakeet231Frontend.readFloat32LE(melBytes, count: 128 * row.frames)
            XCTAssertTrue(expected.allSatisfy { $0.isFinite }, row.name)
            let result = try f.features(audio, validSamples: row.validSamples)
            XCTAssertEqual(result.frames, row.frames, row.name)
            XCTAssertEqual(result.validFrames, row.validFrames, row.name)
            guard result.mel.count == expected.count else {
                XCTFail("Output element count mismatch: \(row.name)")
                continue
            }
            var peak = 0.0, sumSquares = 0.0, validSumSquares = 0.0
            for i in expected.indices {
                let delta = Double(result.mel[i]) - Double(expected[i])
                peak = max(peak, abs(delta))
                sumSquares += delta * delta
                if i % row.frames >= row.validFrames {
                    XCTAssertEqual(result.mel[i].bitPattern, 0, row.name)
                } else {
                    validSumSquares += delta * delta
                }
            }
            let rms = sqrt(sumSquares / Double(expected.count))
            let validRMS = sqrt(validSumSquares / Double(128 * row.validFrames))
            XCTAssertLessThanOrEqual(peak, 1.0e-5, row.name)
            XCTAssertLessThanOrEqual(rms, 1.0e-6, row.name)
            XCTAssertLessThanOrEqual(validRMS, 1.0e-6, row.name)
            print("ASR_SWIFT_FP64 \(row.name) count=\(result.validFrames) peak=\(peak) rms=\(rms) validRMS=\(validRMS)")
        }
    }
}
