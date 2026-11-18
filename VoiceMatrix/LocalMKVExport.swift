import Foundation
import AVFoundation
import AudioToolbox

/// Additional export only. Retain the validated MP4 as AVFoundation's decoder companion.
/// No URL/network access, codecs, credentials, or fallback transcoding are introduced here.
enum LocalMKVExport {
    enum Failure: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self { case .unsupported(let reason): return "MKV export unavailable: \(reason). Your original MP4 is unchanged." }
        }
    }
    /// Parse the actual MPEG-4 ES descriptor. Never guess AAC extensions or scan payload bytes.
    private static func audioSpecificConfig(_ esds: Data) throws -> Data {
        let bytes = [UInt8](esds)
        func descriptor(_ offset: Int, _ end: Int) throws -> (UInt8, Int, Int) {
            guard offset < end else { throw Failure.unsupported("truncated AAC descriptor") }
            let tag = bytes[offset]
            var cursor = offset + 1
            var size = 0
            var terminated = false
            for _ in 0..<4 {
                guard cursor < end else { throw Failure.unsupported("truncated AAC length") }
                let byte = bytes[cursor]; cursor += 1
                size = (size << 7) | Int(byte & 127)
                if byte & 128 == 0 { terminated = true; break }
            }
            guard terminated, size <= end - cursor else { throw Failure.unsupported("invalid AAC length") }
            return (tag,cursor,cursor+size)
        }
        guard bytes.count >= 4, bytes.prefix(4).allSatisfy({ $0 == 0 }) else { throw Failure.unsupported("AAC esds version") }
        let (esTag, esStart, esEnd) = try descriptor(4,bytes.count)
        guard esTag == 3, esEnd - esStart >= 3, bytes[esStart+2] == 0 else { throw Failure.unsupported("AAC ES flags") }
        let (decoderTag, decoderStart, decoderEnd) = try descriptor(esStart+3,esEnd)
        guard decoderTag == 4, decoderEnd-decoderStart >= 13, bytes[decoderStart] == 0x40 else { throw Failure.unsupported("AAC object type") }
        let (configTag, configStart, configEnd) = try descriptor(decoderStart+13,decoderEnd)
        guard configTag == 5 else { throw Failure.unsupported("missing AAC initialization") }
        return Data(bytes[configStart..<configEnd])
    }
    static func export(input: URL, destination: URL, maxBytes: Int64,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        let deadline = Date().addingTimeInterval(180)
        guard input.isFileURL, destination.isFileURL, input.standardizedFileURL != destination.standardizedFileURL,
              destination.pathExtension.lowercased() == "mkv", maxBytes > 0, maxBytes <= 536_870_912,
              !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.unsupported("invalid destination or budget") }
        let inputSize = try input.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard inputSize.isRegularFile == true, let size = inputSize.fileSize, size > 0, size <= 536_870_912 else { throw Failure.unsupported("input size") }
        let parent = destination.deletingLastPathComponent()
        let free = try parent.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        guard let free, free >= maxBytes + 800_000_000 else { throw Failure.unsupported("insufficient free storage") }
        let asset = AVURLAsset(url: input)
        let duration = try await asset.load(.duration).seconds
        let video = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard video.count == 1, audio.count == 1, duration.isFinite, (3...1800).contains(duration) else { throw Failure.unsupported("expected one video and one audio track, 3–1800 seconds") }
        let vf = try await video[0].load(.formatDescriptions)
        let af = try await audio[0].load(.formatDescriptions)
        guard vf.count == 1, af.count == 1, CMFormatDescriptionGetMediaSubType(vf[0]) == kCMVideoCodecType_H264,
              CMFormatDescriptionGetMediaSubType(af[0]) == kAudioFormatMPEG4AAC,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(af[0])?.pointee,
              asbd.mFormatFlags == 2, asbd.mFramesPerPacket == 1024, (1...2).contains(asbd.mChannelsPerFrame) else { throw Failure.unsupported("only AVC and AAC-LC mono/stereo are supported") }
        let rates: [Double] = [96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350]
        guard let rateIndex = rates.firstIndex(of: asbd.mSampleRate),
              let atoms = CMFormatDescriptionGetExtension(vf[0], extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any],
              let avcc = atoms["avcC"] as? Data, avcc.count >= 7, avcc[0] == 1 else { throw Failure.unsupported("missing AVC/AAC configuration") }
        // AAC-LC (object type 2), standard frequency index, explicit mono/stereo configuration.
        let asc = UInt16((2 << 11) | (rateIndex << 7) | (Int(asbd.mChannelsPerFrame) << 3))
        let expectedAAC = Data([UInt8(asc >> 8), UInt8(asc & 255)])
        let audioAtoms = CMFormatDescriptionGetExtension(af[0], extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String: Any]
        var esds = audioAtoms?["esds"] as? Data
        if esds == nil {
            var cookieSize = 0
            if let cookie = CMAudioFormatDescriptionGetMagicCookie(af[0], sizeOut: &cookieSize), cookieSize > 0, cookieSize <= 65536 {
                let data = Data(bytes:cookie,count:cookieSize)
                esds = data.first == 3 ? Data(repeating:0,count:4) + data : data
            }
        }
        guard let esds else { throw Failure.unsupported("missing AAC initialization") }
        let aac = try audioSpecificConfig(esds)
        // Optional standard sync-extension 0x2b7: AAC/SBR type 5, sbrPresentFlag=0.
        guard aac == expectedAAC || aac == expectedAAC + Data([0x56,0xe5,0x00]) else { throw Failure.unsupported("AAC configuration is not the supported explicit LC configuration") }
        let dimensions = CMVideoFormatDescriptionGetDimensions(vf[0])
        guard dimensions.width > 0, dimensions.height > 0, dimensions.width <= 1280, dimensions.height <= 720,
              try await video[0].load(.preferredTransform) == .identity else { throw Failure.unsupported("dimensions or rotation") }
        let temporary = parent.appendingPathComponent(".mkv-export-" + UUID().uuidString, isDirectory:true)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let output = temporary.appendingPathComponent("export.mkv")
        let reader = try AVAssetReader(asset:asset)
        let outputs = [AVAssetReaderTrackOutput(track:video[0],outputSettings:nil), AVAssetReaderTrackOutput(track:audio[0],outputSettings:nil)]
        for o in outputs { o.alwaysCopiesSampleData = false; guard reader.canAdd(o) else { throw Failure.unsupported("compressed reader") }; reader.add(o) }
        guard reader.startReading() else { throw reader.error ?? Failure.unsupported("reader start") }
        defer { reader.cancelReading() }
        let writer = try MatroskaWriter(url:output,maxBytes:maxBytes,tracks:[
            .init(number:1,codec:"V_MPEG4/ISO/AVC",configuration:avcc,width:UInt64(dimensions.width),height:UInt64(dimensions.height),sampleRate:0,channels:0),
            .init(number:2,codec:"A_AAC",configuration:aac,width:0,height:0,sampleRate:asbd.mSampleRate,channels:UInt64(asbd.mChannelsPerFrame))],duration:duration)
        var pending = outputs.map { $0.copyNextSampleBuffer() }
        var previous: [Double] = [-1,-1]
        var counts = [0,0]
        while pending.contains(where: { $0 != nil }) {
            try Task.checkCancellation()
            guard Date() < deadline, counts.reduce(0,+) < 300_000 else { throw Failure.unsupported("export work limit") }
            let index = pending[0] == nil ? 1 : pending[1] == nil ? 0 : (CMSampleBufferGetPresentationTimeStamp(pending[0]!).seconds <= CMSampleBufferGetPresentationTimeStamp(pending[1]!).seconds ? 0 : 1)
            let sample = pending[index]!
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            let dts = CMSampleBufferGetDecodeTimeStamp(sample)
            let length = CMSampleBufferGetDuration(sample).seconds
            guard CMSampleBufferGetNumSamples(sample) == 1, pts.seconds.isFinite, pts.seconds >= 0, pts.seconds >= previous[index],
                  length.isFinite, length > 0, pts.seconds + length <= duration + 0.1,
                  (!dts.isValid || CMTimeCompare(pts,dts) == 0),
                  let block = CMSampleBufferGetDataBuffer(sample),
                  let format = CMSampleBufferGetFormatDescription(sample), CFEqual(format,index == 0 ? vf[0] : af[0]) else { throw Failure.unsupported("reordered, changing, or unsupported sample timing") }
            // Edit-list priming/padding needs an independently verified mapping. Fail closed rather than shift audio.
            for key in [kCMSampleBufferAttachmentKey_TrimDurationAtStart,kCMSampleBufferAttachmentKey_TrimDurationAtEnd] {
                if let attachment = CMGetAttachment(sample,key:key,attachmentModeOut:nil) {
                    guard let trim = attachment as? [String:Any],
                          CMTimeMakeFromDictionary(trim as CFDictionary).seconds == 0 else {
                        throw Failure.unsupported("AAC priming/padding requires the MP4 companion")
                    }
                }
            }
            let byteCount = CMBlockBufferGetDataLength(block)
            guard byteCount > 0, byteCount <= 16_777_216 else { throw Failure.unsupported("sample size") }
            var bytes = Data(count:byteCount)
            let status = bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:byteCount,destination:$0.baseAddress!) }
            guard status == kCMBlockBufferNoErr else { throw Failure.unsupported("sample copy") }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[String:Any]]
            let key = (attachments?.first?[kCMSampleAttachmentKey_NotSync as String] as? Bool) != true
            try writer.append(track:UInt64(index+1),milliseconds:Int64((pts.seconds*1000).rounded()),durationMS:UInt64(max(1,(length*1000).rounded())),key:key,bytes:bytes)
            previous[index] = pts.seconds
            counts[index] += 1
            progress(min(0.99,pts.seconds/duration))
            pending[index] = outputs[index].copyNextSampleBuffer()
            if counts.reduce(0,+) % 256 == 0 { await Task.yield() }
        }
        guard reader.status == .completed, counts.allSatisfy({ $0 > 0 }) else { throw reader.error ?? Failure.unsupported("incomplete read") }
        try writer.finish()
        try Task.checkCancellation()
        // moveItem fails if destination already exists, preserving concurrent/user-created files.
        try FileManager.default.moveItem(at:output,to:destination)
        progress(1)
        return destination
    }
}
