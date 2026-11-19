import CryptoKit
import Foundation
import XCTest
@testable import VoiceMatrix

final class LocalMatroskaReaderTests: XCTestCase {
    private struct Sample {
        let track: UInt64
        let time: Int64
        let duration: UInt64
        let key: Bool
        let padding: UInt64
        let bytes: Data
    }

    private func fixture(_ url: URL, alternateCodec: String? = nil, extraAudio: Bool = false,
                         gap: Bool = false, earlyPadding: Bool = false) throws -> [Sample] {
        let video = MatroskaWriter.Track(number: 1, codec: alternateCodec ?? "V_MPEG4/ISO/AVC",
            configuration: Data([1,66,0,30,255,225,0,4,0x67,66,0,30,1,0,2,0x68,0]),
            width: 640, height: 360, sampleRate: 0, channels: 0)
        let audio = MatroskaWriter.Track(number: 2, codec: "A_AAC", configuration: Data([0x11,0x90]),
            width: 0, height: 0, sampleRate: 48_000, channels: 2, seekPreRollNanoseconds: 21_333_333)
        let writer = try MatroskaWriter(url: url, maxBytes: 100_000,
            tracks: extraAudio ? [video, audio, audio] : [video, audio], duration: 3)
        var samples: [Sample] = (0..<75).map { i in
            Sample(track: 1, time: Int64(i * 40), duration: 40, key: i % 5 == 0,
                   padding: 0, bytes: Data([0,0,0,2,i % 5 == 0 ? 0x65 : 0x41, UInt8(i)]))
        }
        for i in 0..<141 {
            let pts = Int64((Double(i * 1024) / 48).rounded()) + (gap && i == 50 ? 3 : 0)
            samples.append(Sample(track: 2, time: pts, duration: i == 140 ? 13 : 21, key: true,
                padding: i == 140 || (earlyPadding && i == 10) ? 8_000_000 : 0,
                bytes: Data([0xde,0xad,UInt8(i),0x7f])))
        }
        samples.sort { ($0.time, $0.track) < ($1.time, $1.track) }
        for sample in samples {
            try writer.append(track: sample.track, milliseconds: sample.time, durationMS: sample.duration,
                key: sample.key, bytes: sample.bytes, discardPaddingNanoseconds: sample.padding)
        }
        try writer.finish()
        return samples
    }

    private func withDirectory(_ test: (URL) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        try test(dir)
    }

    private func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func read(_ url: URL) throws {
        let reader = try LocalMatroskaReader(url: url, expectedSHA256: hash(url))
        try reader.forEachPacket { _ in }
    }

    func testBothPacketStreamsRoundTripWithoutCompanion() throws {
        try withDirectory { dir in
            let url = dir.appendingPathComponent("only.mkv")
            let expected = try fixture(url)
            let reader = try LocalMatroskaReader(url: url, expectedSHA256: hash(url))
            XCTAssertEqual(reader.video.width, 640)
            XCTAssertEqual(reader.video.height, 360)
            XCTAssertEqual(reader.audio.sampleRate, 48_000)
            XCTAssertEqual(reader.audio.channels, 2)
            XCTAssertEqual(reader.audio.seekPreRollNanoseconds, 21_333_333)
            XCTAssertEqual(reader.audio.configuration, Data([0x11, 0x90]))
            XCTAssertEqual(reader.durationMilliseconds, 3000)
            var i = 0
            try reader.forEachPacket { packet in
                guard i < expected.count else { XCTFail("Extra packet"); return }
                let sample = expected[i]
                XCTAssertEqual(packet.trackNumber, sample.track)
                XCTAssertEqual(packet.presentationMilliseconds, sample.time)
                XCTAssertEqual(packet.durationMilliseconds, sample.duration)
                XCTAssertEqual(packet.isKeyFrame, sample.key)
                XCTAssertEqual(packet.discardPaddingNanoseconds, sample.padding)
                XCTAssertEqual(SHA256.hash(data: packet.bytes), SHA256.hash(data: sample.bytes))
                i += 1
            }
            XCTAssertEqual(i, expected.count)
            try reader.verifyUnchanged()
        }
    }

    func testRejectsUnknownCodecAndExtraTrack() throws {
        try withDirectory { dir in
            let codec = dir.appendingPathComponent("codec.mkv")
            _ = try fixture(codec, alternateCodec: "V_VP9")
            XCTAssertThrowsError(try read(codec))
            let tracks = dir.appendingPathComponent("tracks.mkv")
            _ = try fixture(tracks, extraAudio: true)
            XCTAssertThrowsError(try read(tracks))
        }
    }

    func testRejectsHostileElementSizesLacingTruncationAndUnknownChildren() throws {
        try withDirectory { dir in
            let url = dir.appendingPathComponent("damaged.mkv")
            _ = try fixture(url)
            let clean = try Data(contentsOf: url)
            var unknownSize = clean
            unknownSize[4] = 0xff
            var overflow = clean
            overflow.replaceSubrange(4..<12, with: [0x01,0xff,0xff,0xff,0xff,0xff,0xff,0xfe])
            var lacing = clean
            let block = try XCTUnwrap(clean.range(of: Data([0xa1,0x8a,0x81,0,0,0])))
            lacing[block.upperBound - 1] = 2
            var unknownChild = clean
            let info = try XCTUnwrap(clean.range(of: Data([0x15,0x49,0xa9,0x66])))
            unknownChild[info.lowerBound + 3] = 0x67
            for bytes in [unknownSize, overflow, lacing, unknownChild, Data(clean.dropLast())] {
                try bytes.write(to: url)
                XCTAssertThrowsError(try read(url))
            }
        }
    }

    func testRejectsAudioGapAndNonfinalDiscardPadding() throws {
        try withDirectory { dir in
            let gap = dir.appendingPathComponent("gap.mkv")
            _ = try fixture(gap, gap: true)
            XCTAssertThrowsError(try read(gap))
            let padding = dir.appendingPathComponent("padding.mkv")
            _ = try fixture(padding, earlyPadding: true)
            XCTAssertThrowsError(try read(padding))
        }
    }

    func testRejectsSymlinkWrongSHAReplacementAndInPlaceWrite() throws {
        try withDirectory { dir in
            let url = dir.appendingPathComponent("retained.mkv")
            _ = try fixture(url)
            let expected = try hash(url)
            let link = dir.appendingPathComponent("link.mkv")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
            XCTAssertThrowsError(try LocalMatroskaReader(url: link, expectedSHA256: expected))
            XCTAssertThrowsError(try LocalMatroskaReader(url: url, expectedSHA256: String(repeating: "0", count: 64)))
            let reader = try LocalMatroskaReader(url: url, expectedSHA256: expected)
            XCTAssertThrowsError(try reader.forEachPacket { _ in
                let file = try FileHandle(forWritingTo: url)
                try file.write(contentsOf: Data([0]))
                try file.close()
            })
            _ = try FileManager.default.removeItem(at: url)
            _ = try fixture(url)
            let replacementReader = try LocalMatroskaReader(url: url, expectedSHA256: expected)
            let moved = dir.appendingPathComponent("old.mkv")
            try FileManager.default.moveItem(at: url, to: moved)
            try FileManager.default.copyItem(at: moved, to: url)
            XCTAssertThrowsError(try replacementReader.verifyUnchanged())
        }
    }

    func testCancelledTaskNeverEmitsPacket() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try withDirectory { dir in
                let url = dir.appendingPathComponent("cancelled.mkv")
                _ = try fixture(url)
                XCTAssertThrowsError(try LocalMatroskaReader(url: url, expectedSHA256: hash(url))) {
                    XCTAssertTrue($0 is CancellationError)
                }
            }
        }
        try await task.value
    }
}
