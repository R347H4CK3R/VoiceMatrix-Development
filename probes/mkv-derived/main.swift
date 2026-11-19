import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import CryptoKit
import Darwin
import Foundation

@main enum Probe {
    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("DERIVATION_REJECTED \(error.localizedDescription)\n".utf8))
            exit(error is CancellationError ? 2 : 1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        func url(_ i: Int) -> URL { URL(fileURLWithPath: args[i]) }
        switch args[1] {
        case "stored-policy":
            try testStoredVideoTimingPolicy()
        case "export":
            _ = try await LocalMKVExport.export(input: url(2), destination: url(3), maxBytes: 1_000_000)
        case "video":
            try await captureVideo(url(2), to: url(3))
        case "adts-pcm":
            try captureADTS(url(2), to: url(3), rate: Double(args[4])!, frameLimit: Int(args[5])!)
        case "pcm":
            try await capturePCM(url(2), to: url(3))
        case "derive", "cancel", "cancel-decode", "cancel-pump":
            let cancelRead = args[1] == "cancel"
            let cancelDecode = args[1] == "cancel-decode"
            let cancelPump = args[1] == "cancel-pump"
            let receipt = try await LocalMatroskaDerivedMedia.derive(
                sourceMKV: url(2), expectedSHA256: args[3], destination: url(4),
                maximumBytes: args.count > 5 ? Int64(args[5])! : 536_870_912,
                packetProgress: { count in
                    if count == 9 && cancelRead { withUnsafeCurrentTask { $0?.cancel() } }
                },
                decodeProgress: { count in
                    if count >= 9 && cancelDecode { withUnsafeCurrentTask { $0?.cancel() } }
                },
                appendProgress: { count in
                    if count == 9 && cancelPump { withUnsafeCurrentTask { $0?.cancel() } }
                }
            )
            FileHandle.standardOutput.write(try JSONEncoder().encode(receipt))
        default: fatalError("Unknown test command")
        }
    }

    static func testStoredVideoTimingPolicy() throws {
        typealias Sample = LocalMatroskaDerivedMedia.StoredVideoSample
        func timed(_ pts: Int64, _ duration: Int64, samples: Int = 1, bytes: Int = 7,
                   hasImage: Bool = false) -> Sample {
            Sample(samples: samples, bytes: bytes, hasImage: hasImage,
                   pts: CMTime(value: pts, timescale: 1000), duration: CMTime(value: duration, timescale: 1000))
        }
        func verify(_ observations: [Sample]) throws {
            var cursor = observations.makeIterator()
            try LocalMatroskaDerivedMedia.validateStoredVideoTiming(videoPTS: [0, 57], videoEnd: 91) {
                cursor.next()
            }
        }
        let marker = timed(0, 0, samples: 0, bytes: 0)
        let first = timed(0, 57)
        let second = timed(57, 34)
        try verify([first, second])
        try verify([marker, first, second])
        func terminal(samples: Int = 0, bytes: Int = 0, hasImage: Bool = false,
                      pts: CMTime = .invalid, duration: CMTime = .zero, dts: CMTime = .invalid,
                      emptyMedia: String = "absent", endsPrevious: String = "absent") -> Sample {
            Sample(samples: samples, bytes: bytes, hasImage: hasImage, pts: pts, duration: duration,
                   dts: dts, emptyMedia: emptyMedia, endsPreviousSampleDuration: endsPrevious)
        }
        let endMarker = terminal(pts: CMTime(value: 4_368, timescale: 48_000), emptyMedia: "true")
        try verify([first, second, terminal(), terminal(), endMarker])
        try verify([marker, first, second, terminal(), terminal(), endMarker])
        let malformed = [
            [marker, marker, first, second], [first, second, marker],
            [timed(0, 0, samples: 0, bytes: 1), first, second],
            [timed(0, 0, samples: 0, bytes: 0, hasImage: true), first, second],
            [timed(1, 0, samples: 0, bytes: 0), first, second],
            [timed(0, 1, samples: 0, bytes: 0), first, second],
            [timed(0, 58), second], [first, timed(58, 33)], [first, timed(57, 33)],
            [timed(0, 57, samples: 2), second], [timed(0, 57, bytes: 0), second],
            [first], [first, second, timed(91, 1)],
            [terminal(), first, second], [first, terminal(), second], [first, terminal()],
            [first, second, terminal()], [first, second, terminal(), terminal()],
            [first, second, terminal(), endMarker],
            [first, second, terminal(), terminal(), terminal(), endMarker],
            [first, second, terminal(), terminal(), endMarker, terminal()],
            [first, second, terminal(), terminal(), endMarker, timed(91, 1)],
            [first, second, endMarker, terminal(), terminal()],
            [first, second, terminal(), terminal(), terminal(pts: CMTime(value: 90, timescale: 1000), emptyMedia: "true")],
            [first, second, terminal(), terminal(), terminal(pts: CMTime(value: 91, timescale: 1000), emptyMedia: "other")],
            [first, second, terminal(), terminal(), terminal(bytes: 1, pts: CMTime(value: 91, timescale: 1000), emptyMedia: "true")],
            [first, second, terminal(), terminal(), terminal(samples: 1, pts: CMTime(value: 91, timescale: 1000), emptyMedia: "true")],
            [first, second, terminal(), terminal(), terminal(hasImage: true, pts: CMTime(value: 91, timescale: 1000), emptyMedia: "true")],
            [first, second, terminal(), terminal(), terminal(pts: CMTime(value: 91, timescale: 1000), duration: .invalid, emptyMedia: "true")],
            [first, second, terminal(), terminal(), terminal(pts: CMTime(value: 91, timescale: 1000), dts: .zero, emptyMedia: "true")],
            [first, second, terminal(), terminal(), terminal(pts: CMTime(value: 91, timescale: 1000), emptyMedia: "true", endsPrevious: "true")],
            [first, second, terminal(), marker],
            [first, second, terminal(), timed(91, 1)],
            [first, second, terminal(samples: 1)], [first, second, terminal(bytes: 1)],
            [first, second, terminal(hasImage: true)], [first, second, terminal(pts: .zero)],
            [first, second, terminal(dts: .zero)], [first, second, terminal(duration: .invalid)],
            [first, second, terminal(duration: CMTime(value: 1, timescale: 1000))],
            [first, second, terminal(emptyMedia: "true")],
            [first, second, terminal(endsPrevious: "true")]
        ]
        for (i, observations) in malformed.enumerated() {
            var rejected = false
            do { try verify(observations) }
            catch LocalMatroskaDerivedMedia.Failure.unsupported(_) { rejected = true }
            precondition(rejected, "Malformed stored timing was admitted at case \(i)")
        }
    }

    static func track(_ kind: AVMediaType, asset: AVURLAsset) async throws -> AVAssetTrack {
        let tracks = try await asset.loadTracks(withMediaType: kind)
        precondition(tracks.count == 1)
        return tracks[0]
    }

    /// Independent file-based native oracle. No production MKV reader, AAC
    /// packet callback, QuickTime track edits or AVAssetReader PCM path.
    static func captureADTS(_ url: URL, to destination: URL, rate: Double, frameLimit: Int) throws {
        func require(_ success: Bool, _ context: String) throws {
            if !success { throw NSError(domain: "ADTS oracle: " + context, code: 1) }
        }
        try require((rate == 44_100 || rate == 48_000) && (1...1_000_000).contains(frameLimit), "arguments")
        var reference: ExtAudioFileRef?
        let opened = ExtAudioFileOpenURL(url as CFURL, &reference)
        try require(opened == noErr && reference != nil, "open \(opened)")
        guard let file = reference else { return }
        defer { ExtAudioFileDispose(file) }

        var source = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let format = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source)
        try require(format == noErr && source.mFormatID == kAudioFormatMPEG4AAC &&
                    source.mSampleRate == rate && source.mChannelsPerFrame == 1, "source format \(format)")
        var client = AudioStreamBasicDescription(mSampleRate: rate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        let configured = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                                 UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        try require(configured == noErr, "client format \(configured)")
        var pcm = Data()
        var block = Data(count: 4096 * 2)
        while true {
            var frames: UInt32 = 4096
            let (status, validBytes) = block.withUnsafeMutableBytes { raw in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
                    mNumberChannels: 1, mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                let status = ExtAudioFileRead(file, &frames, &list)
                return (status, list.mBuffers.mDataByteSize)
            }
            try require(status == noErr && frames <= 4096 && validBytes >= frames * 2, "read \(status)")
            if frames == 0 { break }
            try require(pcm.count / 2 + Int(frames) <= frameLimit, "extra frames")
            pcm.append(block.prefix(Int(frames) * 2))
        }
        try pcm.write(to: destination)
    }

    static func capturePCM(_ url: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await track(.audio, asset: asset), outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        precondition(reader.startReading())
        var pcm = Data()
        while let sample = output.copyNextSampleBuffer(), let block = CMSampleBufferGetDataBuffer(sample) {
            let size = CMBlockBufferGetDataLength(block)
            var bytes = Data(count: size)
            let status = bytes.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!)
            }
            precondition(status == noErr)
            pcm.append(bytes)
        }
        precondition(reader.status == .completed && !pcm.isEmpty)
        try pcm.write(to: destination)
    }

    struct Frame: Codable { let ptsMS: Int64; let sha256: String }

    static func captureVideo(_ url: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: url)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: try await track(.video, asset: asset), outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        reader.add(output)
        precondition(reader.startReading())
        var frames: [Frame] = []
        while let sample = output.copyNextSampleBuffer(), let image = CMSampleBufferGetImageBuffer(sample) {
            CVPixelBufferLockBaseAddress(image, .readOnly)
            var digest = SHA256()
            for plane in 0..<CVPixelBufferGetPlaneCount(image) {
                let ptr = CVPixelBufferGetBaseAddressOfPlane(image, plane)!
                let stride = CVPixelBufferGetBytesPerRowOfPlane(image, plane)
                let width = CVPixelBufferGetWidthOfPlane(image, plane) * (plane == 0 ? 1 : 2)
                precondition(stride >= width)
                for row in 0..<CVPixelBufferGetHeightOfPlane(image, plane) {
                    digest.update(data: Data(bytes: ptr.advanced(by: stride * row), count: width))
                }
            }
            CVPixelBufferUnlockBaseAddress(image, .readOnly)
            let pts = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(sample), timescale: 1000,
                                         method: .roundHalfAwayFromZero)
            frames.append(Frame(ptsMS: pts.value, sha256: digest.finalize().map { String(format: "%02x", $0) }.joined()))
        }
        precondition(reader.status == .completed && !frames.isEmpty)
        try JSONEncoder().encode(frames).write(to: destination)
    }
}
