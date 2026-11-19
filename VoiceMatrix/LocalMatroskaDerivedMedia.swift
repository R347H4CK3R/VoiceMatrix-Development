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

    private struct PCMStage {
        let offset: UInt64
        let validAudioFrames: Int64
        let discardFrames: Int64
        let format: AVAudioFormat
    }

    private struct IndexedPacket {
        let offset: UInt64
        let size: Int
        let pts: Int64
        let duration: UInt64
        let key: Bool
        let discardNanoseconds: UInt64
    }

    static func derive(sourceMKV: URL, expectedSHA256: String, destination: URL,
                       maximumBytes: Int64 = 536_870_912,
                       packetProgress: @Sendable (Int) -> Void = { _ in },
                       decodeProgress: @Sendable (Int) -> Void = { _ in },
                       appendProgress: @Sendable (Int) -> Void = { _ in }) async throws -> Receipt {
        let deadline = ContinuousClock.now + .seconds(180)
        var phase = "source-validation"
        var track = "none"
        var count = 0
        var appendedAudioBuffers = 0
        var appendedPCMFrames: Int64 = 0
        var videoPTS = [Int64]()
        var lastMKVPTS: Int64?
        var lastAudioPTS: Int64?
        var lastVideoPTS: Int64?
        var writerState = { "writerStatus=uninitialized audioReady=unavailable videoReady=unavailable" }
        func check() throws {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                let state = "phase=\(phase) track=\(track) packetCount=\(count) appendedAudio=\(appendedAudioBuffers) appendedPCMFrames=\(appendedPCMFrames) appendedVideo=\(videoPTS.count)"
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
        // Validate and spool before starting the writer. Waiting on writer
        // readiness during the sequential MKV callback can prevent the other
        // track from catching up, deadlocking AVFoundation interleaving.
        phase = "spooling-mkv-packets"
        let tapeURL = staging.appendingPathComponent("packets")
        guard fm.createFile(atPath: tapeURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw Failure.destination
        }
        let tape = try FileHandle(forUpdating: tapeURL)
        defer { try? tape.close() }
        let packetIndexLimit = 300_000
        var bytes: UInt64 = 0
        var audioTape = [IndexedPacket]()
        var videoTape = [IndexedPacket]()
        try reader.forEachPacket { packet in
            try check()
            count += 1
            lastMKVPTS = packet.presentationMilliseconds
            track = packet.trackNumber == reader.video.number ? "video" : "audio"
            guard count <= packetIndexLimit, UInt64(packet.bytes.count) <= UInt64(maximumBytes) - bytes else {
                throw Failure.limit
            }
            packetProgress(count)
            try check()
            let indexed = IndexedPacket(offset: bytes, size: packet.bytes.count,
                                        pts: packet.presentationMilliseconds, duration: packet.durationMilliseconds,
                                        key: packet.isKeyFrame, discardNanoseconds: packet.discardPaddingNanoseconds)
            try tape.write(contentsOf: packet.bytes)
            bytes += UInt64(indexed.size)
            if track == "video" { videoTape.append(indexed) }
            else { audioTape.append(indexed) }
        }
        try check() // Final cue and full source hash checks succeeded.
        guard let last = videoTape.last, !audioTape.isEmpty else { throw Failure.unsupported("empty track") }

        phase = "decoding-verified-aac"
        track = "audio"
        let pcm = try stagePCM(tape: tape, offset: bytes, packets: audioTape, track: reader.audio,
                               maximumBytes: UInt64(maximumBytes), check: check, decodeProgress: decodeProgress)
        let audioPackets = Int64(audioTape.count)
        let audioFrames = pcm.validAudioFrames
        let audioPCMFormat = pcm.format
        let audioFrameBytes = Int64(reader.audio.channels * 2)

        phase = "writer-startup"
        track = "none"
        let output = staging.appendingPathComponent("derived.mov")
        let writer = try AVAssetWriter(outputURL: output, fileType: .mov)
        writer.directoryForTemporaryFiles = staging
        let videoFormat = try makeVideoFormat(reader.video)
        let rate = Int32(reader.audio.sampleRate)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: audioPCMFormat.formatDescription)
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

        var videoIndex = 0
        var audioFinished = false, videoFinished = false

        func append(_ item: IndexedPacket, into input: AVAssetWriterInput,
                    format: CMFormatDescription, pts: CMTime, duration: CMTime) throws {
            track = input === video ? "video" : "audio"
            phase = "appending-packet"
            try check()
            try tape.seek(toOffset: item.offset)
            guard let data = try tape.read(upToCount: item.size), data.count == item.size else {
                throw Failure.unsupported("truncated staged packet")
            }
            let buffer = try sample(data, format: format, pts: pts, duration: duration,
                                    count: 1, bytesPerSample: data.count, isKeyFrame: item.key)
            guard input.append(buffer) else { throw Failure.unsupported("video append failed (writerStatus=\(writer.status.rawValue))") }
            lastVideoPTS = item.pts
        }

        while !audioFinished || !videoFinished {
            track = "both"
            phase = "waiting-for-input-readiness"
            try check()
            guard writer.status == .writing else { throw Failure.unsupported("writer stopped (writerStatus=\(writer.status.rawValue))") }
            var progressed = false
            if !audioFinished, audio.isReadyForMoreMediaData {
                track = "audio"
                phase = "appending-pcm"
                let frames = min(4096, audioFrames - appendedPCMFrames)
                let size = Int(frames * audioFrameBytes)
                try tape.seek(toOffset: pcm.offset + UInt64(appendedPCMFrames * audioFrameBytes))
                guard let data = try tape.read(upToCount: size), data.count == size else {
                    throw Failure.unsupported("truncated staged PCM")
                }
                let time = CMTime(value: appendedPCMFrames, timescale: rate)
                let buffer = try sample(data, format: audioPCMFormat.formatDescription, pts: time,
                                        duration: CMTime(value: 1, timescale: rate),
                                        count: Int(frames), bytesPerSample: Int(audioFrameBytes), isKeyFrame: true)
                guard audio.append(buffer) else { throw Failure.unsupported("PCM append failed (writerStatus=\(writer.status.rawValue))") }
                lastAudioPTS = appendedPCMFrames * 1000 / Int64(rate)
                appendedPCMFrames += frames
                appendedAudioBuffers += 1
                appendProgress(appendedAudioBuffers + videoIndex)
                try check()
                if appendedPCMFrames == audioFrames {
                    audio.markAsFinished()
                    audioFinished = true
                }
                progressed = true
            }
            if !videoFinished, video.isReadyForMoreMediaData {
                let item = videoTape[videoIndex]
                let duration = videoIndex + 1 < videoTape.count
                    ? videoTape[videoIndex + 1].pts - item.pts : Int64(item.duration)
                try append(item, into: video, format: videoFormat,
                           pts: CMTime(value: item.pts, timescale: 1000),
                           duration: CMTime(value: duration, timescale: 1000))
                videoIndex += 1
                videoPTS.append(item.pts)
                appendProgress(appendedAudioBuffers + videoIndex)
                try check()
                if videoIndex == videoTape.count {
                    video.markAsFinished()
                    videoFinished = true
                }
                progressed = true
            }
            if !progressed { Darwin.usleep(2_000) }
        }
        let videoEnd = last.pts + Int64(last.duration)
        phase = "finishing-writer"
        track = "none"

        let finish = DispatchSemaphore(value: 0)
        writer.finishWriting { finish.signal() }
        repeat { try check() } while finish.wait(timeout: .now() + .milliseconds(20)) == .timedOut
        guard writer.status == .completed else { throw Failure.unsupported("writer finalization: \(String(describing: writer.error))") }

        // Track metadata is not enough: Apple must expose exactly the selected
        // PCM frames at the same rate, with no leading edit or padding.
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
                       videoEndMilliseconds: videoEnd, discardFrames: pcm.discardFrames)
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

    private static func makeAACFormat(_ track: LocalMatroskaReader.Track) throws -> CMFormatDescription {
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

    /// Decode the exact access units with AudioToolbox's AVFAudio wrapper.
    /// Container-level implicit QuickTime priming is never involved.
    private static func stagePCM(tape: FileHandle, offset: UInt64, packets: [IndexedPacket],
                                 track: LocalMatroskaReader.Track, maximumBytes: UInt64,
                                 check: @escaping () throws -> Void,
                                 decodeProgress: @Sendable (Int) -> Void) throws -> PCMStage {
        let rate = UInt64(track.sampleRate)
        guard let last = packets.last, let maximumPacketSize = packets.lazy.map({ $0.size }).max() else {
            throw Failure.unsupported("no staged AAC")
        }
        let discardFrames = Int64((last.discardNanoseconds * rate + 500_000_000) / 1_000_000_000)
        let expectedDecoderFrames = Int64(packets.count) * 1024
        let validAudioFrames = expectedDecoderFrames - discardFrames
        let frameBytes = Int64(track.channels * 2)
        let decodedBytes = UInt64(validAudioFrames * frameBytes)
        guard offset <= maximumBytes, decodedBytes <= maximumBytes - offset else { throw Failure.limit }
        let encoded = AVAudioFormat(cmAudioFormatDescription: try makeAACFormat(track))
        guard let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: track.sampleRate,
                                      channels: AVAudioChannelCount(track.channels), interleaved: true),
              let converter = AVAudioConverter(from: encoded, to: pcm),
              let output = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: 4096) else {
            throw Failure.unsupported("native AAC converter format")
        }
        let input = AVAudioCompressedBuffer(format: encoded, packetCapacity: 1, maximumPacketSize: maximumPacketSize)
        guard let descriptions = input.packetDescriptions else { throw Failure.unsupported("AAC packet descriptions") }

        var sent = 0
        var decoderProducedFrames: Int64 = 0
        var keptFrames: Int64 = 0
        var eof = false
        while !eof {
            try check()
            let sentBefore = sent
            var inputError: Error?
            var nativeError: NSError?
            output.frameLength = 0
            let status = converter.convert(to: output, error: &nativeError) { (_: AVAudioPacketCount, inputStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? in
                do {
                    try check()
                    guard sent < packets.count else {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    let item = packets[sent]
                    try tape.seek(toOffset: item.offset)
                    guard let data = try tape.read(upToCount: item.size), data.count == item.size else {
                        throw Failure.unsupported("truncated staged AAC")
                    }
                    _ = data.copyBytes(to: input.data.assumingMemoryBound(to: UInt8.self), count: item.size)
                    input.packetCount = 1
                    input.byteLength = UInt32(item.size)
                    descriptions.pointee = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                                        mDataByteSize: UInt32(item.size))
                    sent += 1
                    inputStatus.pointee = .haveData
                    return input
                } catch {
                    inputError = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let inputError { throw inputError }
            if sent > sentBefore { decodeProgress(sent) }
            try check()
            let produced = Int64(output.frameLength)
            guard produced <= expectedDecoderFrames - decoderProducedFrames else {
                throw Failure.unsupported("native AAC decoder returned extra frames")
            }
            decoderProducedFrames += produced
            let keep = min(produced, validAudioFrames - keptFrames)
            if keep > 0 {
                let audioBuffers = UnsafeMutableAudioBufferListPointer(output.mutableAudioBufferList)
                guard audioBuffers.count == 1, let pcmBytes = audioBuffers[0].mData,
                      Int64(audioBuffers[0].mDataByteSize) >= keep * frameBytes else {
                    throw Failure.unsupported("native AAC PCM layout")
                }
                try tape.seek(toOffset: offset + UInt64(keptFrames * frameBytes))
                try tape.write(contentsOf: Data(bytes: pcmBytes, count: Int(keep * frameBytes)))
                keptFrames += keep
            }
            switch status {
            case .endOfStream: eof = true
            case .haveData, .inputRanDry:
                guard produced > 0 || sent > sentBefore else { throw Failure.unsupported("native AAC decoder stalled") }
            case .error: throw Failure.unsupported("native AAC decode (code=\(nativeError?.code ?? 0))")
            @unknown default: throw Failure.unsupported("unknown native AAC decoder state")
            }
        }
        guard sent == packets.count, decoderProducedFrames == expectedDecoderFrames,
              keptFrames == validAudioFrames else {
            throw Failure.unsupported("native AAC decoder frame count: actual=\(decoderProducedFrames) expected=\(expectedDecoderFrames) accessUnits=\(sent)/\(packets.count)")
        }
        return PCMStage(offset: offset, validAudioFrames: validAudioFrames, discardFrames: discardFrames, format: pcm)
    }

    private static func sample(_ data: Data, format: CMFormatDescription,
                               pts: CMTime, duration: CMTime, count: Int, bytesPerSample: Int,
                               isKeyFrame: Bool) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        let size = data.count
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                  blockLength: size, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                  offsetToData: 0, dataLength: size, flags: kCMBlockBufferAssureMemoryNowFlag,
                  blockBufferOut: &block) == noErr, let block,
              data.withUnsafeBytes({ raw in
                  CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: size)
              }) == noErr else { throw Failure.unsupported("packet buffer") }
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: pts, decodeTimeStamp: pts)
        var sampleSize = bytesPerSample
        var output: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                   sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                   sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &output) == noErr,
              let output else { throw Failure.unsupported("sample buffer") }
        if !isKeyFrame {
            guard let array = CMSampleBufferGetSampleAttachmentsArray(output, createIfNecessary: true),
                  let entry = CFArrayGetValueAtIndex(array, 0) else { throw Failure.unsupported("sync attachment") }
            let dictionary = unsafeBitCast(entry, to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
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
        guard !audioSegments.isEmpty, audioSegments.allSatisfy({ !$0.isEmpty && $0.timeMapping.source == $0.timeMapping.target }),
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

        // VideoToolbox can omit duration on a decoded surface. Verify the
        // MOV's actual compressed sample table first, before accepting absence.
        do {
            let storedReader = try AVAssetReader(asset: asset)
            let stored = AVAssetReaderTrackOutput(track: videos[0], outputSettings: nil)
            stored.alwaysCopiesSampleData = false
            guard storedReader.canAdd(stored) else { throw Failure.unsupported("stored video output") }
            storedReader.add(stored)
            guard storedReader.startReading() else { throw Failure.unsupported("stored video read start") }
            defer { if storedReader.status == .reading { storedReader.cancelReading() } }
            try validateStoredVideoTiming(videoPTS: videoPTS, videoEnd: videoEnd, check: check) {
                guard let buffer = stored.copyNextSampleBuffer() else { return nil }
                let bytes = CMSampleBufferGetDataBuffer(buffer).map { CMBlockBufferGetDataLength($0) } ?? 0
                func attachment(_ key: CFString) -> String {
                    guard let value = CMGetAttachment(buffer, key: key, attachmentModeOut: nil) else { return "absent" }
                    return CFEqual(value, kCFBooleanTrue) ? "true" : "other"
                }
                return StoredVideoSample(samples: CMSampleBufferGetNumSamples(buffer), bytes: bytes,
                                         hasImage: CMSampleBufferGetImageBuffer(buffer) != nil,
                                         pts: CMSampleBufferGetPresentationTimeStamp(buffer),
                                         duration: CMSampleBufferGetDuration(buffer),
                                         dts: CMSampleBufferGetDecodeTimeStamp(buffer),
                                         emptyMedia: attachment(kCMSampleBufferAttachmentKey_EmptyMedia),
                                         endsPreviousSampleDuration: attachment(kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration))
            }
            guard storedReader.status == .completed else { throw Failure.unsupported("stored video reader incomplete") }
        }

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
            let decodedDuration = CMSampleBufferGetDuration(buffer)
            guard CMSampleBufferGetPresentationTimeStamp(buffer) == CMTime(value: pts, timescale: 1000),
                  !decodedDuration.isValid || decodedDuration == CMTime(value: next - pts, timescale: 1000) else {
                let observed = CMTimeRange(start: CMSampleBufferGetPresentationTimeStamp(buffer), duration: decodedDuration)
                let expected = CMTimeRange(start: CMTime(value: pts, timescale: 1000),
                                           duration: CMTime(value: next - pts, timescale: 1000))
                throw Failure.unsupported("native video frame timing: index=\(index) actual=\(describe(observed)) expected=\(describe(expected))")
            }
            index += 1
        }
        guard videoReader.status == .completed, index == videoPTS.count else { throw Failure.unsupported("native video frame count") }
    }

    struct StoredVideoSample {
        let samples: Int
        let bytes: Int
        let hasImage: Bool
        let pts: CMTime
        let duration: CMTime
        var dts: CMTime = .invalid
        var emptyMedia = "absent"
        var endsPreviousSampleDuration = "absent"

        var isTerminalNoMedia: Bool {
            samples == 0 && bytes == 0 && !hasImage && !pts.isValid && !dts.isValid &&
                duration.isNumeric && duration == .zero && emptyMedia == "absent" &&
                endsPreviousSampleDuration == "absent"
        }
    }

    /// Permit only the observed leading zero-time marker plus one no-media
    /// observation at the terminal boundary. The caller checks exact track
    /// bounds before running this and requires the reader to complete.
    static func validateStoredVideoTiming(videoPTS: [Int64], videoEnd: Int64,
                                          check: () throws -> Void = {},
                                          nextSample: () -> StoredVideoSample?) throws {
        var index = 0, observations = 0
        while true {
            try check()
            guard let sample = nextSample() else { break }
            observations += 1
            if observations == 1, sample.samples == 0, sample.bytes == 0, !sample.hasImage,
               sample.pts == .zero, sample.duration == .zero {
                continue
            }
            if index == videoPTS.count, sample.isTerminalNoMedia {
                try check()
                guard nextSample() == nil else {
                    throw Failure.unsupported("stored video data after terminal no-media observation")
                }
                break
            }
            guard index < videoPTS.count, sample.samples == 1, sample.bytes > 0, !sample.hasImage else {
                let timing = CMTimeRange(start: sample.pts, duration: sample.duration)
                let end = CMTime(value: videoEnd, timescale: 1000)
                throw Failure.unsupported("unexpected stored video sample or marker at index \(index): storedObservation=\(observations) sampleCount=\(sample.samples) payloadBytes=\(sample.bytes) hasImage=\(sample.hasImage) observedTiming=\(describe(timing)) expectedTrackEnd=\(describeTime(end)) observedDTS=\(describeTime(sample.dts)) emptyMedia=\(sample.emptyMedia) endsPreviousSampleDuration=\(sample.endsPreviousSampleDuration)")
            }
            let pts = videoPTS[index]
            let next = index + 1 < videoPTS.count ? videoPTS[index + 1] : videoEnd
            let expectedPTS = CMTime(value: pts, timescale: 1000)
            let expectedDuration = CMTime(value: next - pts, timescale: 1000)
            guard sample.pts.isNumeric, sample.duration.isNumeric, sample.pts == expectedPTS,
                  sample.duration == expectedDuration else {
                let actual = CMTimeRange(start: sample.pts, duration: sample.duration)
                let expected = CMTimeRange(start: expectedPTS, duration: expectedDuration)
                throw Failure.unsupported("stored video timing: index=\(index) actual=\(describe(actual)) expected=\(describe(expected))")
            }
            index += 1
        }
        guard index == videoPTS.count else { throw Failure.unsupported("stored video frame count") }
    }

    private static func describeTime(_ time: CMTime) -> String {
        "\(time.value)/\(time.timescale) flags=\(time.flags.rawValue) epoch=\(time.epoch)"
    }

    private static func describe(_ range: CMTimeRange) -> String {
        "(start=\(describeTime(range.start)), duration=\(describeTime(range.duration)))"
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
