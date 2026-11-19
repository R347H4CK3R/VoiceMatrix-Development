import AVFoundation
import AudioToolbox
import CoreMedia
import CoreVideo
import CryptoKit
import Darwin
import Foundation

/// Creates only a derived companion, from verified MKV bytes. The caller owns
/// the job directory and may persist the returned provenance in its journal.
enum LocalMatroskaDerivedMedia {
    struct Receipt: Codable, Sendable {
        let mkvSHA256: String
        let movSHA256: String
        let movBytes: Int64
        let audioPackets: Int64
        let audioFrames: Int64
        let audioSampleRate: Int32
        let audioChannels: Int
        let videoFrames: Int
        let videoEndMilliseconds: Int64
        let discardFrames: Int64
    }

    enum Failure: LocalizedError {
        case unsupported(String), destination, limit, deadline(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let reason): return "Native MKV derivation unsupported: \(reason)"
            case .destination: return "Derived MOV destination is unsafe or already exists."
            case .deadline(let context): return "MKV derivation exceeded its 180-second deadline: \(context)"
            case .limit: return "MKV derivation exceeded its time or byte limit."
            }
        }
    }

    static func derive(sourceMKV: URL, expectedSHA256: String, destination: URL,
                       maximumBytes: Int64 = 536_870_912,
                       packetProgress: @Sendable (Int) -> Void = { _ in }) async throws -> Receipt {
        let deadline = ContinuousClock.now + .seconds(180)
        var phase = "source-validation"
        var track = "none"
        var count = 0
        var audioPackets: Int64 = 0
        var videoPTS = [Int64]()
        var lastMKVPTS: Int64?
        var lastAudioPTS: Int64?
        var lastVideoPTS: Int64?
        var writerState = { "writerStatus=uninitialized audioReady=unavailable videoReady=unavailable" }
        func check() throws {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                let state = "phase=\(phase) track=\(track) packetCount=\(count) appendedAudio=\(audioPackets) appendedVideo=\(videoPTS.count)"
                let timing = "lastMKVPTS=\(lastMKVPTS ?? -1) lastAppendedAudioPTS=\(lastAudioPTS ?? -1) lastAppendedVideoPTS=\(lastVideoPTS ?? -1) (milliseconds)"
                throw Failure.deadline("\(state) \(timing) \(writerState())")
            }
        }
        try check()
        let fm = FileManager.default
        let parent = destination.deletingLastPathComponent()
        guard destination.isFileURL, destination.pathExtension.lowercased() == "mov",
              !destination.path.utf8.contains(0),
              (1...536_870_912).contains(maximumBytes) else { throw Failure.destination }
        let parentValues = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard parentValues.isDirectory == true, parentValues.isSymbolicLink != true else { throw Failure.destination }
        var existing = stat()
        guard lstat(destination.path, &existing) != 0, errno == ENOENT else { throw Failure.destination }
        let reader = try LocalMatroskaReader(url: sourceMKV, expectedSHA256: expectedSHA256)
        let staging = parent.appendingPathComponent(".mkv-derived-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: false,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: staging) }
        phase = "writer-startup"
        let output = staging.appendingPathComponent("derived.mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        writer.directoryForTemporaryFiles = staging
        let videoFormat = try makeVideoFormat(reader.video)
        let audioFormat = try makeAudioFormat(reader.audio)
        let rate = Int32(reader.audio.sampleRate)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioFormat)
        writerState = {
            "writerStatus=\(writer.status.rawValue) audioReady=\(audio.isReadyForMoreMediaData) videoReady=\(video.isReadyForMoreMediaData)"
        }
        video.mediaTimeScale = 1000
        writer.movieTimeScale = 1000 * rate / gcd(1000, rate)
        guard writer.canAdd(video), writer.canAdd(audio) else { throw Failure.unsupported("compressed tracks") }
        writer.add(video)
        writer.add(audio)
        guard writer.startWriting() else { throw Failure.unsupported("writer startup: \(String(describing: writer.error))") }
        // On errors or cancellation never leave a live writer using owned scratch.
        defer { if writer.status == .writing { writer.cancelWriting() } }
        writer.startSession(atSourceTime: .zero)

        var pending: LocalMatroskaReader.Packet?
        var removed: Int64 = 0
        var payloadBytes: Int64 = 0

        func append(_ packet: LocalMatroskaReader.Packet, into input: AVAssetWriterInput,
                    format: CMFormatDescription, pts: CMTime, duration: CMTime, trim: CMTime? = nil) throws {
            track = input === video ? "video" : "audio"
            phase = "preparing-append"
            try check()
            payloadBytes += Int64(packet.bytes.count)
            guard payloadBytes <= maximumBytes else { throw Failure.limit }
            phase = "waiting-for-input-readiness"
            while !input.isReadyForMoreMediaData {
                try check()
                guard writer.status == .writing else { throw Failure.unsupported("writer stopped") }
                // This synchronous packet callback is off the UI actor.
                // The monotonic deadline also bounds a stalled writer input.
                Darwin.usleep(2_000)
            }
            phase = "appending-packet"
            let buffer = try sample(packet, format: format, pts: pts, duration: duration, endTrim: trim)
            guard input.append(buffer) else { throw Failure.unsupported("packet append: \(String(describing: writer.error))") }
            if input === video { lastVideoPTS = packet.presentationMilliseconds }
            else { lastAudioPTS = packet.presentationMilliseconds }
        }

        func appendVideo(_ packet: LocalMatroskaReader.Packet, duration: Int64) throws {
            try append(packet, into: video, format: videoFormat,
                       pts: CMTime(value: packet.presentationMilliseconds, timescale: 1000),
                       duration: CMTime(value: duration, timescale: 1000))
            videoPTS.append(packet.presentationMilliseconds)
        }

        phase = "reading-mkv-packets"
        try reader.forEachPacket { packet in
            try check()
            count += 1
            lastMKVPTS = packet.presentationMilliseconds
            track = packet.trackNumber == reader.video.number ? "video" : "audio"
            phase = "packet-progress-callback"
            packetProgress(count)
            try check()
            if packet.trackNumber == reader.video.number {
                if let previous = pending {
                    // PTS is authoritative where the individually rounded
                    // MKV duration and next video timestamp differ by 1 ms.
                    try appendVideo(previous, duration: packet.presentationMilliseconds - previous.presentationMilliseconds)
                }
                pending = packet
            } else {
                // The reader already validated that MKV PTS agrees with this
                // exact AAC frame clock. SeekPreRoll is not a leading trim.
                removed = Int64((packet.discardPaddingNanoseconds * UInt64(rate) + 500_000_000) / 1_000_000_000)
                let trim = removed == 0 ? nil : CMTime(value: removed, timescale: rate)
                try append(packet, into: audio, format: audioFormat,
                           pts: CMTime(value: audioPackets * 1024, timescale: rate),
                           duration: CMTime(value: 1024, timescale: rate), trim: trim)
                audioPackets += 1
            }
            phase = "reading-mkv-packets"
            track = "none"
        }
        guard let last = pending else { throw Failure.unsupported("no video") }
        try appendVideo(last, duration: Int64(last.durationMilliseconds))
        let videoEnd = last.presentationMilliseconds + Int64(last.durationMilliseconds)
        let audioFrames = audioPackets * 1024 - removed
        phase = "finishing-writer"
        track = "none"
        video.markAsFinished()
        audio.markAsFinished()

        let finish = DispatchSemaphore(value: 0)
        writer.finishWriting { finish.signal() }
        repeat { try check() } while finish.wait(timeout: .now() + .milliseconds(20)) == .timedOut
        guard writer.status == .completed else { throw Failure.unsupported("writer finalization: \(String(describing: writer.error))") }

        // Track metadata is not enough: Apple must expose the exact PCM frames
        // after trim, with no implicit leading priming removal or extra padding.
        phase = "hashing-derived-output"
        let digest = try hash(output, maximumBytes: maximumBytes, check: check)
        phase = "verifying-native-output"
        try await verifyNative(output, rate: rate, channels: reader.audio.channels, audioFrames: audioFrames,
                               videoPTS: videoPTS, videoEnd: videoEnd, width: reader.video.width, height: reader.video.height,
                               check: check)
        phase = "rechecking-source"
        try reader.verifyUnchanged()
        try check()
        // Same-volume atomic create, never replacing an existing item, even
        // if another writer races this job after our initial destination check.
        guard link(output.path, destination.path) == 0 else { throw Failure.destination }
        return Receipt(mkvSHA256: expectedSHA256.lowercased(), movSHA256: digest.0, movBytes: digest.1,
                       audioPackets: audioPackets, audioFrames: audioFrames, audioSampleRate: rate,
                       audioChannels: reader.audio.channels, videoFrames: videoPTS.count,
                       videoEndMilliseconds: videoEnd, discardFrames: removed)
    }

    private static func gcd(_ a: Int32, _ b: Int32) -> Int32 {
        b == 0 ? a : gcd(b, a % b)
    }

    private static func makeVideoFormat(_ track: LocalMatroskaReader.Track) throws -> CMFormatDescription {
        var description: CMFormatDescription?
        let extensions = [kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String:
                          ["avcC": track.configuration]] as CFDictionary
        let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: kCMVideoCodecType_H264,
                       width: Int32(track.width), height: Int32(track.height), extensions: extensions,
                       formatDescriptionOut: &description)
        guard status == noErr, let description else { throw Failure.unsupported("H.264 format (\(status))") }
        return description
    }

    private static func makeAudioFormat(_ track: LocalMatroskaReader.Track) throws -> CMFormatDescription {
        var asbd = AudioStreamBasicDescription(mSampleRate: track.sampleRate, mFormatID: kAudioFormatMPEG4AAC,
                       mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue), mBytesPerPacket: 0, mFramesPerPacket: 1024,
                       mBytesPerFrame: 0, mChannelsPerFrame: UInt32(track.channels), mBitsPerChannel: 0, mReserved: 0)
        // Core Audio's AAC cookie is the MPEG-4 ES descriptor, not the
        // Matroska AudioSpecificConfig by itself. Preserve every ASC byte.
        let ascCount = UInt8(track.configuration.count)
        let cookie = Data([0x03, 23 + ascCount, 0, 1, 0,
                           0x04, 15 + ascCount, 0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0x05, ascCount]) + track.configuration + Data([0x06, 1, 2])
        var description: CMAudioFormatDescription?
        let status = cookie.withUnsafeBytes {
            CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                magicCookieSize: $0.count, magicCookie: $0.baseAddress, extensions: nil, formatDescriptionOut: &description)
        }
        guard status == noErr, let description else { throw Failure.unsupported("AAC format (\(status))") }
        return description
    }

    private static func sample(_ packet: LocalMatroskaReader.Packet, format: CMFormatDescription,
                               pts: CMTime, duration: CMTime, endTrim: CMTime?) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let size = packet.bytes.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                  blockLength: size, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                  offsetToData: 0, dataLength: size, flags: kCMBlockBufferAssureMemoryNowFlag,
                  blockBufferOut: &block) == noErr, let block,
              packet.bytes.withUnsafeBytes({ raw in
                  CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: size)
              }) == noErr else { throw Failure.unsupported("packet buffer") }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: pts)
        var sampleSize = size
        var output: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                   sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                   sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &output) == noErr,
              let output else { throw Failure.unsupported("sample buffer") }
        if !packet.isKeyFrame {
            guard let array = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true),
                  let entry = CFArrayGetValueAtIndex(array, 0) else { throw Failure.unsupported("sync attachment") }
            let dictionary = unsafeBitCast(entry, to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if let endTrim {
            CMSetAttachment(output, key: kCMSampleBufferAttachmentKey_TrimDurationAtEnd,
                            value: CMTimeCopyAsDictionary(endTrim, allocator: kCFAllocatorDefault),
                            attachmentMode: kCMAttachmentMode_ShouldPropagate)
        }
        return output
    }

    private static func verifyNative(_ url: URL, rate: Int32, channels: Int, audioFrames: Int64,
                                     videoPTS: [Int64], videoEnd: Int64, width: Int, height: Int,
                                     check: () throws -> Void) async throws {
        let asset = AVURLAsset(url: url)
        let videos = try await asset.loadTracks(withMediaType: .video)
        let audios = try await asset.loadTracks(withMediaType: .audio)
        guard videos.count == 1, audios.count == 1 else { throw Failure.unsupported("derived track count") }
        let videoRange = try await videos[0].load(.timeRange)
        let audioRange = try await audios[0].load(.timeRange)
        let audioSegments = try await audios[0].load(.segments)
        try check()
        let expectedVideo = CMTimeRange(start: .zero, duration: CMTime(value: videoEnd, timescale: 1000))
        let expectedAudio = CMTimeRange(start: .zero, duration: CMTime(value: audioFrames, timescale: rate))
        guard !audioSegments.isEmpty, audioSegments.allSatisfy({ !$0.isEmpty }),
              videoRange.start == expectedVideo.start, audioRange.start == expectedAudio.start,
              videoRange.duration == expectedVideo.duration,
              audioRange.duration == expectedAudio.duration else {
            let mappings = audioSegments.prefix(8).map { segment in
                "empty=\(segment.isEmpty) source=\(describe(segment.timeMapping.source)) target=\(describe(segment.timeMapping.target))"
            }.joined(separator: "; ")
            throw Failure.unsupported("native track bounds or AAC trim: actualVideo=\(describe(videoRange)) expectedVideo=\(describe(expectedVideo)) actualAudio=\(describe(audioRange)) expectedAudio=\(describe(expectedAudio)) audioSegmentMappings=[\(mappings)] (count=\(audioSegments.count))")
        }

        let audioReader = try AVAssetReader(asset: asset)
        let pcm = AVAssetReaderTrackOutput(track: audios[0], outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        guard audioReader.canAdd(pcm) else { throw Failure.unsupported("PCM output") }
        audioReader.add(pcm)
        guard audioReader.startReading() else { throw Failure.unsupported("PCM decode start") }
        defer { if audioReader.status == .reading { audioReader.cancelReading() } }
        var frames: Int64 = 0
        while let buffer = pcm.copyNextSampleBuffer() {
            try check()
            guard let format = CMSampleBufferGetFormatDescription(buffer),
                  let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  asbd.mFormatID == kAudioFormatLinearPCM, asbd.mBitsPerChannel == 16,
                  asbd.mSampleRate == Double(rate), asbd.mChannelsPerFrame == UInt32(channels),
                  CMSampleBufferGetPresentationTimeStamp(buffer) == CMTime(value: frames, timescale: rate) else {
                throw Failure.unsupported("native PCM clock or format")
            }
            let n = CMSampleBufferGetNumSamples(buffer)
            guard n > 0, Int64(n) <= audioFrames - frames,
                  let data = CMSampleBufferGetDataBuffer(buffer),
                  CMBlockBufferGetDataLength(data) == n * channels * 2 else { throw Failure.unsupported("native PCM padding") }
            frames += Int64(n)
        }
        guard audioReader.status == .completed, frames == audioFrames else { throw Failure.unsupported("native PCM frame count") }

        let videoReader = try AVAssetReader(asset: asset)
        let decoded = AVAssetReaderTrackOutput(track: videos[0], outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ])
        guard videoReader.canAdd(decoded) else { throw Failure.unsupported("video output") }
        videoReader.add(decoded)
        guard videoReader.startReading() else { throw Failure.unsupported("video decode start") }
        defer { if videoReader.status == .reading { videoReader.cancelReading() } }
        var index = 0
        while let buffer = decoded.copyNextSampleBuffer() {
            try check()
            guard index < videoPTS.count, let image = CMSampleBufferGetImageBuffer(buffer),
                  CVPixelBufferGetWidth(image) == width, CVPixelBufferGetHeight(image) == height else {
                throw Failure.unsupported("native video frame count or dimensions")
            }
            let pts = videoPTS[index]
            let next = index + 1 < videoPTS.count ? videoPTS[index + 1] : videoEnd
            guard CMSampleBufferGetPresentationTimeStamp(buffer) == CMTime(value: pts, timescale: 1000),
                  CMSampleBufferGetDuration(buffer) == CMTime(value: next - pts, timescale: 1000) else {
                throw Failure.unsupported("native video frame timing")
            }
            index += 1
        }
        guard videoReader.status == .completed, index == videoPTS.count else { throw Failure.unsupported("native video frame count") }
    }

    private static func describe(_ range: CMTimeRange) -> String {
        func describeTime(_ time: CMTime) -> String {
            "\(time.value)/\(time.timescale) flags=\(time.flags.rawValue) epoch=\(time.epoch)"
        }
        return "(start=\(describeTime(range.start)), duration=\(describeTime(range.duration)))"
    }

    private static func hash(_ url: URL, maximumBytes: Int64, check: () throws -> Void) throws -> (String, Int64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        var bytes: Int64 = 0
        while true {
            try check()
            guard let data = try handle.read(upToCount: 1_048_576), !data.isEmpty else { break }
            bytes += Int64(data.count)
            guard bytes <= maximumBytes else { throw Failure.limit }
            digest.update(data: data)
        }
        guard bytes > 0 else { throw Failure.unsupported("empty output") }
        return (digest.finalize().map { String(format: "%02x", $0) }.joined(), bytes)
    }
}
