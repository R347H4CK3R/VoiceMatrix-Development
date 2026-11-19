import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// A bounded reader for the LocalMKVExport/MatroskaWriter subset only.
/// Callbacks write to unpublished scratch; do not commit until iteration and
/// final source verification both succeed. No MP4 or alternate source is used.
final class LocalMatroskaReader {
    enum Failure: LocalizedError {
        case unsupported, bounds, unsafe, changed
        var errorDescription: String? {
            switch self {
            case .unsupported: return "Unsupported local MKV structure, codec or timeline."
            case .bounds: return "Local MKV exceeds a bound or is incomplete."
            case .unsafe: return "Local MKV source is not a safe regular file."
            case .changed: return "Local MKV source does not match the verified acquisition."
            }
        }
    }

    struct Track {
        let number: UInt64
        let codec: String
        let configuration: Data
        let width: Int
        let height: Int
        let sampleRate: Double
        let channels: Int
        let seekPreRollNanoseconds: UInt64
    }

    struct Packet {
        let trackNumber: UInt64
        let presentationMilliseconds: Int64
        let durationMilliseconds: UInt64
        let isKeyFrame: Bool
        let discardPaddingNanoseconds: UInt64
        let bytes: Data
    }

    let video: Track
    let audio: Track
    let durationMilliseconds: Double
    private let source: Source
    private let packetStart: Int64
    private let segmentStart: Int64

    init(url: URL, expectedSHA256: String, maximumBytes: Int64 = 536_870_912) throws {
        try Task.checkCancellation()
        let source = try Source(url, expectedSHA256, maximumBytes)
        try source.verify()
        let c = Cursor(source, start: 0)
        let header = try c.element(0x1A45DFA3, in: source.size)
        guard try c.uint(0x4286, in: header) == 1,
              try c.uint(0x42F7, in: header) == 1,
              try c.uint(0x42F2, in: header) == 4,
              try c.uint(0x42F3, in: header) == 8,
              try c.body(0x4282, in: header, max: 8) == Data("matroska".utf8),
              try c.uint(0x4287, in: header) == 4,
              try c.uint(0x4285, in: header) == 2,
              c.position == header else { throw Failure.unsupported }

        // The sole permitted unknown length is the exact Segment marker emitted
        // by the writer. All subscope lengths below must be finite.
        guard try c.bytes(12, in: source.size) == Data([0x18,0x53,0x80,0x67,0x01,0xff,0xff,0xff,0xff,0xff,0xff,0xff]) else {
            throw Failure.unsupported
        }
        segmentStart = c.position
        let info = try c.element(0x1549A966, in: source.size)
        guard try c.uint(0x2AD7B1, in: info) == 1_000_000 else { throw Failure.unsupported }
        let duration = Double(bitPattern: try c.fixed64(0x4489, in: info))
        let producer = Data("VoiceMatrix".utf8)
        guard (3000...1_800_000).contains(duration),
              try c.body(0x4D80, in: info, max: producer.count) == producer,
              try c.body(0x5741, in: info, max: producer.count) == producer,
              c.position == info else { throw Failure.unsupported }

        let tracks = try c.element(0x1654AE6B, in: source.size)
        video = try Self.readTrack(c, in: tracks, number: 1)
        audio = try Self.readTrack(c, in: tracks, number: 2)
        guard c.position == tracks else { throw Failure.unsupported }
        packetStart = c.position
        durationMilliseconds = duration
        self.source = source
        try source.checkIdentity()
    }

    func verifyUnchanged() throws { try source.verify() }

    func forEachPacket(_ consume: (Packet) throws -> Void) throws {
        try source.checkIdentity()
        let c = Cursor(source, start: packetStart)
        var lastPTS: Int64 = -1
        var videoPTS: Int64?
        var videoDuration: Int64 = 0
        var audioEndFrames: UInt64 = 0
        var audioPackets: UInt64 = 0
        var audioPadded = false
        var packetCount = 0
        var keyCues: [(time: UInt64, position: UInt64)] = []
        let rate = UInt64(audio.sampleRate)
        while try c.peek(in: source.size) == 0x1f {
            try source.checkWork()
            packetCount += 1
            guard packetCount <= 300_000 else { throw Failure.bounds }
            let clusterOffset = c.position - segmentStart
            let cluster = try c.element(0x1F43B675, in: source.size)
            let encodedPTS = try c.uint(0xE7, in: cluster)
            guard encodedPTS <= 1_800_100 else { throw Failure.bounds }
            let pts = Int64(encodedPTS)
            guard pts >= lastPTS else { throw Failure.unsupported }
            lastPTS = pts
            let group = try c.element(0xA0, in: cluster)
            let block = try c.element(0xA1, in: group)
            let header = try c.bytes(4, in: block)
            guard header[1] == 0, header[2] == 0, header[3] == 0,
                  header[0] == 0x81 || header[0] == 0x82 else { throw Failure.unsupported }
            let videoPacket = header[0] == 0x81
            let size = block - c.position
            guard (1...16_777_216).contains(size) else { throw Failure.bounds }
            let bytes = try c.bytes(Int(size), in: block)
            let encodedDuration = try c.uint(0x9B, in: group)
            guard (1...1_800_000).contains(encodedDuration) else { throw Failure.bounds }
            var key = true
            var padding: UInt64 = 0
            if videoPacket {
                if let previous = videoPTS {
                    guard pts > previous, abs(pts - previous - videoDuration) <= 1 else { throw Failure.unsupported }
                } else if pts != 0 { throw Failure.unsupported }
                if c.position < group {
                    guard let previous = videoPTS,
                          try c.fixed64(0xFB, in: group) == UInt64(bitPattern: previous - pts) else { throw Failure.unsupported }
                    key = false
                }
                try Self.validateAVCPacket(bytes)
                videoPTS = pts
                videoDuration = Int64(encodedDuration)
                if key { keyCues.append((encodedPTS, UInt64(clusterOffset))) }
            } else {
                guard !audioPadded, encodedPTS == Self.rounded(audioPackets * 1024 * 1000, over: rate) else {
                    throw Failure.unsupported
                }
                var frames: UInt64 = 1024
                if c.position < group {
                    padding = try c.fixed64(0x75A2, in: group)
                    guard (1...140_000_000).contains(padding) else { throw Failure.unsupported }
                    let removed = Self.rounded(padding * rate, over: 1_000_000_000)
                    guard (1...1023).contains(removed),
                          Self.rounded(removed * 1_000_000_000, over: rate) == padding else {
                        throw Failure.unsupported
                    }
                    frames -= removed
                    audioPadded = true
                }
                // The writer computes milliseconds via Double; at an exact
                // half-millisecond, accept either nearest integer.
                guard abs(Int64(encodedDuration * rate) - Int64(frames * 1000)) * 2 <= Int64(rate)
                        || (encodedDuration == 1 && frames * 1000 < rate) else { throw Failure.unsupported }
                audioEndFrames += frames
                audioPackets += 1
            }
            guard c.position == group, group == cluster else { throw Failure.unsupported }
            try consume(Packet(trackNumber: videoPacket ? 1 : 2, presentationMilliseconds: pts,
                durationMilliseconds: encodedDuration, isKeyFrame: key,
                discardPaddingNanoseconds: padding, bytes: bytes))
        }

        guard let videoPTS, audioPackets > 0, !keyCues.isEmpty else { throw Failure.unsupported }
        let videoEnd = Double(videoPTS + videoDuration)
        let audioEnd = Double(audioEndFrames * 1000) / Double(rate)
        guard abs(videoEnd - audioEnd) <= 251,
              abs(durationMilliseconds - max(videoEnd, audioEnd)) <= 1 else { throw Failure.unsupported }

        let cues = try c.element(0x1C53BB6B, in: source.size)
        guard cues - c.position <= 8_000_000 else { throw Failure.bounds }
        for expected in keyCues {
            try source.checkWork()
            let cue = try c.element(0xBB, in: cues)
            guard try c.uint(0xB3, in: cue) == expected.time else { throw Failure.unsupported }
            let position = try c.element(0xB7, in: cue)
            guard try c.uint(0xF7, in: position) == 1,
                  try c.uint(0xF1, in: position) == expected.position,
                  c.position == position, position == cue else { throw Failure.unsupported }
        }
        guard c.position == cues, cues == source.size else { throw Failure.unsupported }
        try source.verify()
    }

    private static func rounded(_ value: UInt64, over divisor: UInt64) -> UInt64 {
        (value + divisor / 2) / divisor
    }

    private static func readTrack(_ c: Cursor, in limit: Int64, number: UInt64) throws -> Track {
        let entry = try c.element(0xAE, in: limit)
        let isVideo = number == 1
        let codec = isVideo ? "V_MPEG4/ISO/AVC" : "A_AAC"
        guard try c.uint(0xD7, in: entry) == number,
              try c.uint(0x73C5, in: entry) == number,
              try c.uint(0x83, in: entry) == number,
              try c.uint(0x9C, in: entry) == 0,
              try c.body(0x86, in: entry, max: 16) == Data(codec.utf8) else { throw Failure.unsupported }
        let configuration = try c.body(0x63A2, in: entry, max: isVideo ? 65_536 : 5)
        var width = 0, height = 0, channels = 0
        var rate: Double = 0
        var preRoll: UInt64 = 0
        if isVideo {
            let video = try c.element(0xE0, in: entry)
            let w = try c.uint(0xB0, in: video), h = try c.uint(0xBA, in: video)
            guard (1...1280).contains(w), (1...720).contains(h), c.position == video else { throw Failure.unsupported }
            width = Int(w)
            height = Int(h)
            try validateAVCConfiguration(configuration)
        } else {
            if try c.peek(in: entry) == 0x56 {
                preRoll = try c.uint(0x56BB, in: entry)
                guard preRoll > 0 else { throw Failure.unsupported }
            }
            let audio = try c.element(0xE1, in: entry)
            rate = Double(bitPattern: try c.fixed64(0xB5, in: audio))
            let count = try c.uint(0x9F, in: audio)
            let rates: [Double] = [96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350]
            guard let index = rates.firstIndex(of: rate), (1...2).contains(count), c.position == audio,
                  preRoll == 0 || preRoll == rounded(1024 * 1_000_000_000, over: UInt64(rate)) else {
                throw Failure.unsupported
            }
            channels = Int(count)
            let bits = UInt16((2 << 11) | (index << 7) | (channels << 3))
            let expected = Data([UInt8(bits >> 8), UInt8(bits & 255)])
            guard configuration == expected || configuration == expected + Data([0x56,0xe5,0x00]) else {
                throw Failure.unsupported
            }
        }
        guard c.position == entry else { throw Failure.unsupported }
        return Track(number: number, codec: codec, configuration: configuration, width: width, height: height,
                     sampleRate: rate, channels: channels, seekPreRollNanoseconds: preRoll)
    }

    private static func validateAVCConfiguration(_ d: Data) throws {
        guard d.count >= 7, d[0] == 1, d[4] == 0xff, d[5] & 0xe0 == 0xe0,
              d[5] & 0x1f > 0 else { throw Failure.unsupported }
        var cursor = 6
        func parameterSets(_ count: Int, type: UInt8) throws {
            for _ in 0..<count {
                guard d.count - cursor >= 2 else { throw Failure.unsupported }
                let size = Int(d[cursor]) * 256 + Int(d[cursor + 1])
                cursor += 2
                guard size > 0, size <= d.count - cursor, d[cursor] & 0x9f == type else { throw Failure.unsupported }
                cursor += size
            }
        }
        try parameterSets(Int(d[5] & 0x1f), type: 7)
        guard cursor < d.count, d[cursor] > 0 else { throw Failure.unsupported }
        let ppsCount = Int(d[cursor])
        cursor += 1
        try parameterSets(ppsCount, type: 8)
        if cursor < d.count {
            let extensionProfiles: [UInt8] = [44,83,86,100,110,118,122,128,134,135,138,139,144,244]
            guard extensionProfiles.contains(d[1]), d.count - cursor >= 4,
                  d[cursor] & 0xfc == 0xfc, d[cursor + 1] & 0xf8 == 0xf8,
                  d[cursor + 2] & 0xf8 == 0xf8 else { throw Failure.unsupported }
            let extensions = Int(d[cursor + 3])
            cursor += 4
            try parameterSets(extensions, type: 13)
        }
        guard cursor == d.count else { throw Failure.unsupported }
    }

    private static func validateAVCPacket(_ d: Data) throws {
        var cursor = 0
        var units = 0
        while cursor < d.count {
            units += 1
            if units % 1024 == 0 { try Task.checkCancellation() }
            guard d.count - cursor >= 5 else { throw Failure.unsupported }
            let size = d[cursor..<(cursor + 4)].reduce(0) { ($0 << 8) | Int($1) }
            cursor += 4
            guard size > 0, size <= d.count - cursor, d[cursor] & 0x80 == 0,
                  (1...23).contains(d[cursor] & 0x1f) else { throw Failure.unsupported }
            cursor += size
        }
    }

    private final class Source {
        let size: Int64
        private let fd: Int32
        private let url: URL
        private let original: stat
        private let digest: Data
        private let started = DispatchTime.now().uptimeNanoseconds

        init(_ url: URL, _ sha: String, _ maxBytes: Int64) throws {
            let hex = Array(sha.utf8)
            guard url.isFileURL, !url.path.utf8.contains(0), hex.count == 64,
                  (1...536_870_912).contains(maxBytes) else { throw Failure.unsafe }
            func digit(_ byte: UInt8) throws -> UInt8 {
                switch byte {
                case 48...57: return byte - 48
                case 65...70: return byte - 55
                case 97...102: return byte - 87
                default: throw Failure.unsafe
                }
            }
            digest = try Data(stride(from: 0, to: 64, by: 2).map { i in
                try digit(hex[i]) * 16 + digit(hex[i + 1])
            })
            let file = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard file >= 0 else { throw Failure.unsafe }
            var before = stat()
            guard fstat(file, &before) == 0, before.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                _ = close(file)
                throw Failure.unsafe
            }
            guard before.st_size > 0, Int64(before.st_size) <= maxBytes else {
                _ = close(file)
                throw Failure.bounds
            }
            fd = file
            self.url = url
            original = before
            size = Int64(before.st_size)
        }

        deinit { _ = close(fd) }

        func checkWork() throws {
            try Task.checkCancellation()
            guard DispatchTime.now().uptimeNanoseconds - started < 180_000_000_000 else { throw Failure.bounds }
        }

        func read(_ from: Int64, _ count: Int) throws -> Data {
            try checkWork()
            guard from >= 0, from <= size, count > 0, Int64(count) <= size - from,
                  count <= 16_777_216 else { throw Failure.bounds }
            var bytes = Data(count: count)
            try bytes.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
                guard let base = buffer.baseAddress else { throw Failure.bounds }
                var copied = 0
                while copied < count {
                    try checkWork()
                    let n = pread(fd, base.advanced(by: copied), count - copied, off_t(from + Int64(copied)))
                    if n < 0 && errno == EINTR { continue }
                    guard n > 0 else { throw Failure.changed }
                    copied += n
                }
            }
            return bytes
        }

        func verify() throws {
            try checkIdentity()
            var hasher = SHA256()
            var offset: Int64 = 0
            while offset < size {
                let chunk = try read(offset, Int(min(1_048_576, size - offset)))
                hasher.update(data: chunk)
                offset += Int64(chunk.count)
            }
            guard Data(hasher.finalize()) == digest else { throw Failure.changed }
            try checkIdentity()
        }

        func checkIdentity() throws {
            try checkWork()
            var descriptor = stat(), named = stat()
            guard fstat(fd, &descriptor) == 0, lstat(url.path, &named) == 0,
                  matches(descriptor), matches(named) else { throw Failure.changed }
        }

        private func matches(_ value: stat) -> Bool {
            guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
                  value.st_dev == original.st_dev, value.st_ino == original.st_ino,
                  value.st_size == original.st_size else { return false }
#if canImport(Darwin)
            let m = value.st_mtimespec, c = value.st_ctimespec
            let initialM = original.st_mtimespec, initialC = original.st_ctimespec
#else
            let m = value.st_mtim, c = value.st_ctim
            let initialM = original.st_mtim, initialC = original.st_ctim
#endif
            return m.tv_sec == initialM.tv_sec && m.tv_nsec == initialM.tv_nsec &&
                c.tv_sec == initialC.tv_sec && c.tv_nsec == initialC.tv_nsec
        }
    }

    private final class Cursor {
        let source: Source
        private(set) var position: Int64
        private var window = Data()
        private var windowStart: Int64 = 0

        init(_ source: Source, start: Int64) {
            self.source = source
            position = start
        }

        func peek(in limit: Int64) throws -> UInt8 {
            guard position < limit else { throw Failure.bounds }
            if position < windowStart || position - windowStart >= Int64(window.count) {
                window = try source.read(position, Int(min(65_536, source.size - position)))
                windowStart = position
            }
            return window[Int(position - windowStart)]
        }

        private func byte(in limit: Int64) throws -> UInt8 {
            let value = try peek(in: limit)
            position += 1
            return value
        }

        func bytes(_ count: Int, in limit: Int64) throws -> Data {
            guard position <= limit, count >= 0, Int64(count) <= limit - position else { throw Failure.bounds }
            guard count > 0 else { return Data() }
            let value: Data
            if count <= 65_536 {
                _ = try peek(in: limit)
                let offset = Int(position - windowStart)
                if count <= window.count - offset { value = window.subdata(in: offset..<(offset+count)) }
                else { value = try source.read(position, count) }
            } else { value = try source.read(position, count) }
            position += Int64(count)
            return value
        }

        func element(_ expectedID: UInt64, in limit: Int64) throws -> Int64 {
            let id = try vint(in: limit, isID: true)
            guard id == expectedID else { throw Failure.unsupported }
            let length = try vint(in: limit, isID: false)
            guard length <= UInt64(limit - position) else { throw Failure.bounds }
            return position + Int64(length)
        }

        func uint(_ id: UInt64, in limit: Int64) throws -> UInt64 {
            let end = try element(id, in: limit)
            let count = end - position
            guard (1...8).contains(count) else { throw Failure.unsupported }
            let first = try byte(in: end)
            guard count == 1 || first != 0 else { throw Failure.unsupported }
            var value = UInt64(first)
            while position < end { value = (value << 8) | UInt64(try byte(in: end)) }
            return value
        }

        func fixed64(_ id: UInt64, in limit: Int64) throws -> UInt64 {
            let end = try element(id, in: limit)
            guard end - position == 8 else { throw Failure.unsupported }
            var value: UInt64 = 0
            while position < end { value = (value << 8) | UInt64(try byte(in: end)) }
            return value
        }

        func body(_ id: UInt64, in limit: Int64, max: Int) throws -> Data {
            let end = try element(id, in: limit)
            guard end - position <= Int64(max) else { throw Failure.bounds }
            return try bytes(Int(end - position), in: end)
        }

        private func vint(in limit: Int64, isID: Bool) throws -> UInt64 {
            let first = try byte(in: limit)
            guard first != 0 else { throw Failure.unsupported }
            let count = first.leadingZeroBitCount + 1
            guard count <= (isID ? 4 : 8), Int64(count - 1) <= limit - position else { throw Failure.bounds }
            let marker = UInt8(1 << (8 - count))
            var value = UInt64(isID ? first : first ^ marker)
            for _ in 1..<count { value = (value << 8) | UInt64(try byte(in: limit)) }
            if !isID {
                guard value != (UInt64(1) << (7 * count)) - 1,
                      count == 1 || value >= (UInt64(1) << (7 * (count - 1))) - 1 else {
                    throw Failure.unsupported
                }
            }
            return value
        }
    }
}
