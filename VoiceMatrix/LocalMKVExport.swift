import Foundation

/// Additional bounded export only. The MP4 decoder companion is always retained.
/// Reads original compressed sample tables, not AVFoundation's edited/grouped buffers.
enum LocalMKVExport {
    enum Failure: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self { case .unsupported(let reason): return "MKV export unavailable: \(reason). Your original MP4 is unchanged." }
        }
    }
    /// The actual AudioSpecificConfig is authoritative. ASBD flags may be unspecified (0),
    /// but explicit contradictory object types are rejected rather than overwritten.
    static func validateAACConfiguration(_ configuration: Data, sampleRate: Double, channels: UInt32,
                                         formatFlags: UInt32, framesPerPacket: UInt32) throws {
        let rates: [Double] = [96000,88200,64000,48000,44100,32000,24000,22050,16000,12000,11025,8000,7350]
        guard let index = rates.firstIndex(of: sampleRate), (1...2).contains(channels),
              formatFlags == 0 || formatFlags == 2, framesPerPacket == 1024 else {
            throw Failure.unsupported("unsupported AAC description flags=\(formatFlags), frames=\(framesPerPacket), channels=\(channels), rate=\(sampleRate)")
        }
        let asc = UInt16((2 << 11) | (index << 7) | (Int(channels) << 3))
        let expected = Data([UInt8(asc >> 8), UInt8(asc & 255)])
        // Optional standard sync-extension 0x2b7: AAC/SBR type 5, sbrPresentFlag=0.
        guard configuration == expected || configuration == expected + Data([0x56,0xe5,0x00]) else {
            throw Failure.unsupported("AAC configuration is not the supported explicit LC configuration")
        }
    }
    static func export(input: URL, destination: URL, maxBytes: Int64,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        try Task.checkCancellation()
        let deadline = Date().addingTimeInterval(180)
        guard input.isFileURL, destination.isFileURL, input.standardizedFileURL != destination.standardizedFileURL,
              destination.pathExtension.lowercased() == "mkv", maxBytes > 0, maxBytes <= 536_870_912,
              !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.unsupported("invalid destination or budget") }
        let parent = destination.deletingLastPathComponent()
        let values = try parent.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey,.volumeAvailableCapacityForImportantUsageKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              let free = values.volumeAvailableCapacityForImportantUsage, free >= maxBytes + 800_000_000 else {
            throw Failure.unsupported("unsafe destination or insufficient free storage")
        }
        let source = try MP4SampleTable(url:input)
        let video = source.video, audio = source.audio
        guard video.width > 0, video.height > 0, video.width <= 1280, video.height <= 720 else {
            throw Failure.unsupported("video dimensions exceed supported export")
        }
        try validateAACConfiguration(audio.configuration,sampleRate:audio.sampleRate,channels:UInt32(audio.channels),formatFlags:0,framesPerPacket:1024)
        let temporary = parent.appendingPathComponent(".mkv-export-" + UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:false)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let output = temporary.appendingPathComponent("export.mkv")
        let writer = try MatroskaWriter(url:output,maxBytes:maxBytes,tracks:[
            .init(number:1,codec:"V_MPEG4/ISO/AVC",configuration:video.configuration,width:UInt64(video.width),height:UInt64(video.height),sampleRate:0,channels:0),
            .init(number:2,codec:"A_AAC",configuration:audio.configuration,width:0,height:0,sampleRate:audio.sampleRate,channels:UInt64(audio.channels),seekPreRollNanoseconds:UInt64((audio.seekPreRoll*1_000_000_000).rounded()))],duration:source.duration)
        let tracks = [video,audio]
        var positions = [0,0]
        var packets = 0
        while positions[0] < video.samples.count || positions[1] < audio.samples.count {
            try Task.checkCancellation()
            guard Date() < deadline, packets < 300_000 else { throw Failure.unsupported("export work limit") }
            let index: Int
            if positions[0] == video.samples.count { index = 1 }
            else if positions[1] == audio.samples.count { index = 0 }
            else { index = video.samples[positions[0]].timestamp <= audio.samples[positions[1]].timestamp ? 0 : 1 }
            let sample = tracks[index].samples[positions[index]]
            let bytes = try source.read(sample)
            try writer.append(track:UInt64(index+1),milliseconds:Int64((sample.timestamp*1000).rounded()),
                              durationMS:UInt64(max(1,(sample.duration*1000).rounded())),key:sample.key,bytes:bytes,discardPaddingNanoseconds:sample.discardPaddingNanoseconds)
            positions[index] += 1
            packets += 1
            progress(min(0.99,sample.timestamp/source.duration))
            if packets % 256 == 0 { await Task.yield() }
        }
        try source.verifyUnchanged()
        try writer.finish()
        try Task.checkCancellation()
        try FileManager.default.moveItem(at:output,to:destination)
        progress(1)
        return destination
    }
}
