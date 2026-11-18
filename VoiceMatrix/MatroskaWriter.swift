import Foundation

/// Narrow streaming Matroska muxer. Payloads are compressed AVC/AAC, never transcoded.
final class MatroskaWriter {
    enum Failure: Error { case invalid, limit }
    struct Track {
        let number: UInt64
        let codec: String
        let configuration: Data
        let width: UInt64
        let height: UInt64
        let sampleRate: Double
        let channels: UInt64
    }
    private let handle: FileHandle
    private let limit: Int64
    private(set) var count: Int64 = 0
    private var cues = Data()
    private var segmentStart: Int64 = 0
    private var lastTime: Int64 = -1
    private var previousVideoTime: Int64?
    static func integer(_ value: UInt64) -> Data {
        var big = value.bigEndian
        let bytes = withUnsafeBytes(of: &big) { Data($0) }
        return Data(bytes.drop(while: { $0 == 0 }).isEmpty ? [0] : Array(bytes.drop(while: { $0 == 0 })))
    }
    static func element(_ id: UInt64, _ body: Data) -> Data {
        var length = UInt64(body.count)
        var size = 1
        while length >= (UInt64(1) << (7 * size)) - 1 { size += 1 }
        length |= UInt64(1) << (7 * size)
        var big = length.bigEndian
        return integer(id) + withUnsafeBytes(of: &big) { Data($0.suffix(size)) } + body
    }
    static func uint(_ id: UInt64, _ value: UInt64) -> Data { element(id, integer(value)) }
    static func string(_ id: UInt64, _ value: String) -> Data { element(id, Data(value.utf8)) }
    static func float(_ id: UInt64, _ value: Double) -> Data {
        var bits = value.bitPattern.bigEndian
        return element(id, withUnsafeBytes(of: &bits) { Data($0) })
    }
    init(url: URL, maxBytes: Int64, tracks: [Track], duration: Double) throws {
        guard maxBytes > 0, duration.isFinite, duration >= 3, duration <= 1800 else { throw Failure.invalid }
        limit = maxBytes
        // Caller owns an exclusive temporary directory. No existing output is opened/truncated.
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw Failure.invalid }
        handle = try FileHandle(forWritingTo: url)
        try write(Self.element(0x1A45DFA3, Self.uint(0x4286, 1) + Self.uint(0x42F7, 1) + Self.uint(0x42F2, 4) + Self.uint(0x42F3, 8) + Self.string(0x4282, "matroska") + Self.uint(0x4287, 4) + Self.uint(0x4285, 2)))
        // Unknown-sized Segment is permitted for streaming; every child has a definite size.
        try write(Data([0x18,0x53,0x80,0x67,0x01,0xff,0xff,0xff,0xff,0xff,0xff,0xff]))
        segmentStart = count
        try write(Self.element(0x1549A966, Self.uint(0x2AD7B1, 1_000_000) + Self.float(0x4489, duration * 1000) + Self.string(0x4D80, "VoiceMatrix") + Self.string(0x5741, "VoiceMatrix")))
        var entries = Data()
        for t in tracks {
            var entry = Self.uint(0xD7,t.number) + Self.uint(0x73C5,t.number) + Self.uint(0x83,t.number == 1 ? 1 : 2) + Self.uint(0x9C,0) + Self.string(0x86,t.codec) + Self.element(0x63A2,t.configuration)
            if t.number == 1 {
                entry += Self.element(0xE0, Self.uint(0xB0,t.width) + Self.uint(0xBA,t.height))
            } else {
                entry += Self.element(0xE1, Self.float(0xB5,t.sampleRate) + Self.uint(0x9F,t.channels))
            }
            entries += Self.element(0xAE,entry)
        }
        try write(Self.element(0x1654AE6B,entries))
    }
    deinit { try? handle.close() }
    private func write(_ data: Data) throws {
        guard data.count <= limit - count else { throw Failure.limit }
        try handle.write(contentsOf:data)
        count += Int64(data.count)
    }
    func append(track: UInt64, milliseconds: Int64, durationMS: UInt64, key: Bool, bytes: Data) throws {
        guard (track == 1 || track == 2), milliseconds >= lastTime, milliseconds >= 0, milliseconds <= 1_800_100, !bytes.isEmpty, bytes.count <= 16_777_216 else { throw Failure.invalid }
        lastTime = milliseconds
        let position = count - segmentStart
        // One finite cluster per packet bounds memory and signed block time offsets.
        let block = Data([UInt8(0x80 | track),0,0,0]) + bytes
        var group = Self.element(0xA1,block) + Self.uint(0x9B,durationMS)
        if track == 1 {
            if !key {
                guard let previousVideoTime, previousVideoTime < milliseconds else { throw Failure.invalid }
                var reference = (previousVideoTime - milliseconds).bigEndian
                group += Self.element(0xFB,withUnsafeBytes(of: &reference) { Data($0) })
            }
            previousVideoTime = milliseconds
        }
        try write(Self.element(0x1F43B675, Self.uint(0xE7,UInt64(milliseconds)) + Self.element(0xA0,group)))
        if track == 1 && key {
            cues += Self.element(0xBB, Self.uint(0xB3,UInt64(milliseconds)) + Self.element(0xB7, Self.uint(0xF7,1) + Self.uint(0xF1,UInt64(position))))
            guard cues.count <= 8_000_000 else { throw Failure.limit }
        }
    }
    func finish() throws {
        try write(Self.element(0x1C53BB6B,cues))
        try handle.synchronize()
        try handle.close()
    }
}
