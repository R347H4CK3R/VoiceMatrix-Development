import AVFoundation
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
        let malformed = [
            [marker, marker, first, second], [first, second, marker],
            [timed(0, 0, samples: 0, bytes: 1), first, second],
            [timed(0, 0, samples: 0, bytes: 0, hasImage: true), first, second],
            [timed(1, 0, samples: 0, bytes: 0), first, second],
            [timed(0, 1, samples: 0, bytes: 0), first, second],
            [timed(0, 58), second], [first, timed(58, 33)], [first, timed(57, 33)],
            [timed(0, 57, samples: 2), second], [timed(0, 57, bytes: 0), second],
            [first], [first, second, timed(91, 1)]
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
