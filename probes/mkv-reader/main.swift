import CryptoKit
import Foundation

/// Host-only fixture probe. Precomputes a source packet oracle, deletes the MP4,
/// then reads only the actual MatroskaWriter output.
@main
enum MatroskaReaderProbe {
    static func main() throws {
        let original = URL(fileURLWithPath: CommandLine.arguments[1])
        let mkv = URL(fileURLWithPath: CommandLine.arguments[2])
        let expected = try buildFixture(original, mkv)
        try FileManager.default.removeItem(at: original)
        let hash = digest(try Data(contentsOf: mkv))
        let reader = try LocalMatroskaReader(url: mkv, expectedSHA256: hash)
        var count = 0
        try reader.forEachPacket { packet in
            precondition(count < expected.count)
            precondition(digest(packet.bytes) == expected[count].sha)
            precondition(packet.trackNumber == expected[count].track)
            precondition(packet.presentationMilliseconds == expected[count].pts)
            precondition(packet.durationMilliseconds == expected[count].duration)
            precondition(packet.discardPaddingNanoseconds == expected[count].padding)
            precondition(packet.isKeyFrame == expected[count].key)
            count += 1
        }
        precondition(count == expected.count)
        try reader.verifyUnchanged()
        print("WRITER_READER_H264_AAC_SHA_TIMELINE_OK")
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    struct Expected {
        let sha: String
        let track: UInt64
        let pts: Int64
        let duration: UInt64
        let padding: UInt64
        let key: Bool
    }

    static func buildFixture(_ original: URL, _ mkv: URL) throws -> [Expected] {
        let mp4 = try MP4SampleTable(url: original)
        let tracks = [mp4.video, mp4.audio]
        let writerTracks = tracks.enumerated().map { index, track in
            MatroskaWriter.Track(number: UInt64(index+1), codec: index == 0 ? "V_MPEG4/ISO/AVC" : "A_AAC",
                configuration: track.configuration, width: UInt64(track.width), height: UInt64(track.height),
                sampleRate: track.sampleRate, channels: UInt64(track.channels),
                seekPreRollNanoseconds: UInt64((track.seekPreRoll * 1_000_000_000).rounded()))
        }
        let writer = try MatroskaWriter(url: mkv, maxBytes: 4_000_000, tracks: writerTracks, duration: mp4.duration)
        let samples = tracks.enumerated().flatMap { index, track in track.samples.map { (index + 1, $0) } }
            .sorted { ($0.1.timestamp, $0.0) < ($1.1.timestamp, $1.0) }
        var expected: [Expected] = []
        for (index, sample) in samples {
            let bytes = try mp4.read(sample)
            let time = Int64((sample.timestamp * 1000).rounded())
            let duration = UInt64(max(1, (sample.duration * 1000).rounded()))
            try writer.append(track: UInt64(index), milliseconds: time, durationMS: duration,
                key: sample.key, bytes: bytes, discardPaddingNanoseconds: sample.discardPaddingNanoseconds)
            expected.append(Expected(sha: digest(bytes), track: UInt64(index), pts: time,
                duration: duration, padding: sample.discardPaddingNanoseconds, key: sample.key))
        }
        try writer.finish()
        return expected
    }
}
