import Foundation
import AVFoundation
import CoreMedia
import Darwin
import CryptoKit
@preconcurrency import CoreML
import FluidAudio

/// Local model bytes are verified before loading. No downloads, purge or service fallback.
enum LocalSpeakerDiarization {
    struct Analysis: Codable, Sendable {
        let modelRevision: String
        let seconds: Double
        let segments: [LocalSpeakerPolicy.Segment]
        let speakerWindows: [LocalSpeakerPolicy.Speaker]
        var selectionPolicyVersion: Int? = nil
        var rawOverlap: LocalOverlapPolicy.Evidence? = nil
    }
    enum Failure: LocalizedError {
        case bundleUnavailable, invalidBundle, invalidAudio, invalidTimeline, resourceBound
        case invalidRetainedPCMFrames(actual: Int, expected: Int)
        var errorDescription: String? {
            switch self {
            case .bundleUnavailable: return "Bundled speaker analysis is missing. Install a complete standalone build. No laptop or server fallback was used."
            case .invalidBundle: return "Bundled speaker analysis failed its integrity check. Existing voices and media were retained."
            case .invalidAudio: return "Speaker analysis needs one readable audio track in local media. No speakers were invented."
            case .invalidTimeline: return "The audio timeline has a gap or offset over 50 milliseconds, which could select the wrong speaker. Export the media with a continuous audio track and import it again. Your original and existing voices were retained."
            case .invalidRetainedPCMFrames: return "Speaker analysis could not decode the complete retained clip. No review was saved."
            case .resourceBound: return "Speaker analysis exceeded this app's safety limit. Retained media and voices are unchanged."
            }
        }
    }
    private struct Lock: Decodable { struct File: Decodable { let size:Int; let sha256:String }; let revision:String; let files:[String:File] }
    private static let revision = "df2625ac79a7ac6b65ad868fee6d80f320da4232"
    static func validate(_ analysis: Analysis) throws { _ = try validatedForCurrentPolicy(analysis) }
    /// Older retained analyses keep their exact legacy-window check before upgrade.
    /// Raw segments/model revision must validate; arbitrary stored crops are never trusted.
    static func validatedForCurrentPolicy(_ analysis: Analysis) throws -> Analysis {
        guard analysis.modelRevision == revision else { throw Failure.invalidBundle }
        if analysis.selectionPolicyVersion == 5 {
            guard let evidence=analysis.rawOverlap else {throw Failure.invalidAudio}
            try LocalOverlapPolicy.validate(evidence)
            guard evidence.modelRevision==revision,evidence.duration==analysis.seconds else {throw Failure.invalidAudio}
            let candidates=try LocalSpeakerPolicy.speakerWindows(analysis.segments,duration:analysis.seconds,candidateLimit:6)
            let expected=try excludingRawOverlap(candidates,evidence:evidence)
            guard expected==analysis.speakerWindows else {throw Failure.invalidAudio}
            return analysis
        }
        guard analysis.rawOverlap == nil else {throw Failure.invalidAudio}
        guard analysis.selectionPolicyVersion == nil || analysis.selectionPolicyVersion == 1 || analysis.selectionPolicyVersion == 2 || analysis.selectionPolicyVersion == 3 || analysis.selectionPolicyVersion == 4 else { throw Failure.invalidBundle }
        let expected = try LocalSpeakerPolicy.speakerWindows(analysis.segments,duration:analysis.seconds,includeFallbacks:(analysis.selectionPolicyVersion ?? 1) >= 2,joinSameSpeakerPauses:(analysis.selectionPolicyVersion ?? 1) >= 3,candidateLimit:analysis.selectionPolicyVersion == 4 ? 6 : 3)
        guard expected == analysis.speakerWindows else { throw Failure.invalidAudio }
        let windows = try LocalSpeakerPolicy.speakerWindows(analysis.segments,duration:analysis.seconds,candidateLimit:6)
        return Analysis(modelRevision:analysis.modelRevision,seconds:analysis.seconds,segments:analysis.segments,speakerWindows:windows,selectionPolicyVersion:4)
    }
    static func excludingRawOverlap(_ speakers:[LocalSpeakerPolicy.Speaker],evidence:LocalOverlapPolicy.Evidence) throws -> [LocalSpeakerPolicy.Speaker] {
        try LocalOverlapPolicy.validate(evidence)
        return try speakers.map { speaker in
            let safe=try speaker.windows.filter {try LocalOverlapPolicy.allows(start:$0.start,end:$0.end,evidence:evidence)}
            return LocalSpeakerPolicy.Speaker(speaker:speaker.speaker,windows:safe)
        }
    }
    static func analyze(source: URL, bundle: URL? = Bundle.main.url(forResource:"Diarization",withExtension:nil), retainedClipFrames: Int? = nil, progress: @escaping @Sendable (String) -> Void) async throws -> Analysis {
        guard let bundle else { throw Failure.bundleUnavailable }
        let worker = Task.detached(priority:.userInitiated) {
            try Task.checkCancellation()
            progress("Checking bundled speaker-analysis hashes.")
            try verify(bundle)
            progress("Decoding local audio for speaker analysis.")
            let sourceHash=try sourceDigest(source)
            let samples: [Float]
            if let retainedClipFrames {
                samples = try decodeRetainedClip(source, frames: retainedClipFrames, sourceSHA256: sourceHash)
            } else {
                samples = try await decode(source,progress:progress)
            }
            try Task.checkCancellation()
            progress("Loading bundled speaker-analysis models. No network is used.")
            let start = Date()
            func model(_ name: String, cpuOnly: Bool = false) throws -> MLModel {
                try Task.checkCancellation()
                let config = MLModelConfiguration(); config.computeUnits = cpuOnly ? .cpuOnly : .all
                return try MLModel(contentsOf:bundle.appendingPathComponent(name+".mlmodelc"),configuration:config)
            }
            let psiData = try Data(contentsOf:bundle.appendingPathComponent("plda-parameters.json"))
            guard let object = try JSONSerialization.jsonObject(with:psiData) as? [String:Any],
                  let tensors = object["tensors"] as? [String:Any], let psi = tensors["psi"] as? [String:Any],
                  let base64 = psi["data_base64"] as? String, let bytes = Data(base64Encoded:base64), bytes.count == 128*4 else { throw Failure.invalidBundle }
            let values: [Double] = bytes.withUnsafeBytes { raw in (0..<128).map { Double(Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self)))) } }
            guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw Failure.invalidBundle }
            let models = try OfflineDiarizerModels(segmentationModel:model("Segmentation"),fbankModel:model("FBank",cpuOnly:true),embeddingModel:model("Embedding"),pldaRhoModel:model("PldaRho"),pldaPsi:values,compilationDuration:Date().timeIntervalSince(start))
            var config = OfflineDiarizerConfig()
            config.segmentation.batchSize = 1
            config.embedding.batchSize = 1
            config.embedding.excludeOverlap = true
            config.postProcessing.exclusiveSegments = false
            config.exposeChunkEmbeddings = false
            let manager = OfflineDiarizerManager(config:config)
            manager.initialize(models:models)
            try Task.checkCancellation()
            progress("Analyzing speaker turns locally; model activity updates follow completed chunks.")
            let prepared = try await manager.prepare(audio:samples) { done,total in progress("Speaker analysis processed \(done) of \(total) chunks.") }
            try Task.checkCancellation()
            let result=try manager.cluster(prepared)
            let duration = Double(samples.count)/16_000
            let activity=prepared.segmentationEvidence
            guard activity.numChunks==activity.speakerWeights.count,activity.numChunks==activity.chunkOffsets.count,
                  activity.numSpeakers>=1,activity.speakerWeights.allSatisfy({$0.count==activity.numFrames && $0.allSatisfy({$0.count==activity.numSpeakers})}) else {throw Failure.invalidAudio}
            let rawOverlap=try LocalOverlapPolicy.build(weights:activity.speakerWeights,offsets:activity.chunkOffsets,
                frameDuration:activity.frameDuration,duration:duration,sourceSHA256:sourceHash,modelRevision:revision)
            guard try sourceDigest(source)==sourceHash else {throw Failure.invalidAudio}
            let segments = result.segments.map { LocalSpeakerPolicy.Segment(speaker:$0.speakerId,start:Double($0.startTimeSeconds),end:Double($0.endTimeSeconds)) }
            let candidates = try LocalSpeakerPolicy.speakerWindows(segments,duration:duration,candidateLimit:6)
            let windows=try excludingRawOverlap(candidates,evidence:rawOverlap)
            return Analysis(modelRevision:revision,seconds:duration,segments:segments,speakerWindows:windows,selectionPolicyVersion:5,rawOverlap:rawOverlap)
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private static func sourceDigest(_ source:URL) throws -> String {
        let v=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard source.isFileURL,v.isRegularFile==true,v.isSymbolicLink != true,let size=v.fileSize,(1...536_870_912).contains(size) else {throw Failure.invalidAudio}
        let handle=try FileHandle(forReadingFrom:source);defer {try? handle.close()}
        var hash=SHA256(),read=0
        while let data=try handle.read(upToCount:1_048_576),!data.isEmpty {
            try Task.checkCancellation();read+=data.count;guard read<=size else {throw Failure.invalidAudio};hash.update(data:data)
        }
        guard read==size else {throw Failure.invalidAudio}
        return hash.finalize().map{String(format:"%02x",$0)}.joined()
    }
    static func verify(_ root: URL) throws {
        let lockURL = root.appendingPathComponent("resource-lock.json")
        guard let data = try? Data(contentsOf:lockURL), data.count <= 65_536,
              SHA256.hash(data:data).map({String(format:"%02x",$0)}).joined() == "137ad0aba1483d0ba3c74cb5380ab05f5cd76a5eb47aa69b9de41c353315e7e0",
              let lock = try? JSONDecoder().decode(Lock.self,from:data), lock.revision == revision, (21...40).contains(lock.files.count) else { throw Failure.invalidBundle }
        for (name,entry) in lock.files {
            try Task.checkCancellation()
            let parts = name.split(separator:"/",omittingEmptySubsequences:false)
            guard !parts.isEmpty, !name.contains("\\"), parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }), entry.size > 0, entry.size <= 25_000_000 else { throw Failure.invalidBundle }
            var path = root
            for part in parts { path.appendPathComponent(String(part)); let v = try path.resourceValues(forKeys:[.isSymbolicLinkKey]); guard v.isSymbolicLink != true else { throw Failure.invalidBundle } }
            let v = try path.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
            guard v.isRegularFile == true, v.fileSize == entry.size else { throw Failure.invalidBundle }
            let handle = try FileHandle(forReadingFrom:path); defer { try? handle.close() }
            var hash = SHA256()
            while let bytes = try handle.read(upToCount:1_048_576), !bytes.isEmpty { try Task.checkCancellation(); hash.update(data:bytes) }
            guard hash.finalize().map({String(format:"%02x",$0)}).joined() == entry.sha256 else { throw Failure.invalidBundle }
        }
        for name in ["Segmentation","FBank","Embedding","PldaRho"] {
            guard lock.files[name+".mlmodelc/weights/weight.bin"] != nil else { throw Failure.invalidBundle }
        }
    }
    /// Only the canonical Float32 stereo WAV produced by retained clip handoff.
    /// AVAssetReader's implicit resampling may drop tail frames. Read the bounded
    /// canonical PCM, then use normal converter priming and explicitly drain EOF.
    static func decodeRetainedClip(_ source: URL, frames: Int, sourceSHA256: String) throws -> [Float] {
        try Task.checkCancellation()
        guard (132_300...441_000).contains(frames) else { throw Failure.resourceBound }
        guard source.isFileURL else { throw Failure.invalidAudio }
        let byteCount = 44 + frames * 8
        let fd = open(source.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { throw Failure.invalidAudio }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_size == off_t(byteCount) else { throw Failure.invalidAudio }
        var bytes = Data()
        bytes.reserveCapacity(byteCount)
        while bytes.count < byteCount {
            try Task.checkCancellation()
            guard let block = try handle.read(upToCount: min(65_536, byteCount - bytes.count)), !block.isEmpty else {
                throw Failure.invalidAudio
            }
            bytes.append(block)
        }
        guard (try handle.read(upToCount: 1))?.isEmpty ?? true,
              SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == sourceSHA256 else {
            throw Failure.invalidAudio
        }
        let canonical = bytes.withUnsafeBytes { raw -> Bool in
            func u32(_ offset: Int) -> UInt32 { UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) }
            func u16(_ offset: Int) -> UInt16 { UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) }
            return u32(0) == 0x46464952 && u32(4) == UInt32(byteCount - 8)  // RIFF
                && u32(8) == 0x45564157 && u32(12) == 0x20746d66 && u32(16) == 16  // WAVEfmt
                && u16(20) == 3 && u16(22) == 2 && u32(24) == 44_100 && u32(28) == 352_800
                && u16(32) == 8 && u16(34) == 32 && u32(36) == 0x61746164 && u32(40) == UInt32(frames * 8) // data
        }
        guard canonical,
              let native = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let inputPCM = AVAudioPCMBuffer(pcmFormat: native, frameCapacity: 8192),
              let outputPCM = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: 4096),
              let converter = AVAudioConverter(from: native, to: output) else { throw Failure.invalidAudio }
        converter.primeMethod = .normal
        // Quantize the source duration to the nearest 16 kHz sample; never pad or crop.
        let expected = (frames * 16_000 + 22_050) / 44_100
        let pcm = bytes
        var samples: [Float] = []
        samples.reserveCapacity(expected)
        var cursor = 0, empty = 0, sourceEOF = false
        var inputError: Error?
        for _ in 0..<256 {
            try Task.checkCancellation()
            outputPCM.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: outputPCM, error: &error) { requested, state in
                do {
                    try Task.checkCancellation()
                    if cursor == frames {
                        sourceEOF = true
                        state.pointee = .endOfStream
                        return nil
                    }
                    let count = min(Int(requested), Int(inputPCM.frameCapacity), frames - cursor)
                    guard count > 0, let mono = inputPCM.floatChannelData?[0] else { throw Failure.invalidAudio }
                    try pcm.withUnsafeBytes { raw in
                        for i in 0..<count {
                            if i % 2048 == 0 { try Task.checkCancellation() }
                            let offset = 44 + (cursor + i) * 8
                            let left = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)))
                            let right = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self)))
                            guard left.isFinite, right.isFinite, abs(left) <= 1.000001, abs(right) <= 1.000001 else {
                                throw Failure.invalidAudio
                            }
                            mono[i] = 0.5 * left + 0.5 * right
                        }
                    }
                    cursor += count
                    inputPCM.frameLength = AVAudioFrameCount(count)
                    state.pointee = .haveData
                    return inputPCM
                } catch {
                    inputError = error
                    state.pointee = .noDataNow
                    return nil
                }
            }
            try Task.checkCancellation()
            if let inputError { throw inputError }
            guard error == nil, status != .error,
                  let data = outputPCM.floatChannelData?[0] else { throw Failure.invalidAudio }
            let count = Int(outputPCM.frameLength)
            guard count <= expected - samples.count else {
                throw Failure.invalidRetainedPCMFrames(actual: samples.count + count, expected: expected)
            }
            for i in 0..<count {
                if i % 2048 == 0 { try Task.checkCancellation() }
                let value = data[i]
                guard value.isFinite, abs(value) <= 1.01 else { throw Failure.invalidAudio }
                samples.append(value)
            }
            if status == .endOfStream {
                guard sourceEOF, cursor == frames else { throw Failure.invalidAudio }
                guard samples.count == expected else {
                    throw Failure.invalidRetainedPCMFrames(actual: samples.count, expected: expected)
                }
                return samples
            }
            empty = count == 0 ? empty + 1 : 0
            guard empty < 3 else { throw Failure.invalidAudio }
        }
        throw Failure.resourceBound
    }
    private static func decode(_ source: URL, progress: @Sendable (String)->Void) async throws -> [Float] {
        guard source.isFileURL else { throw Failure.invalidAudio }
        let v = try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard v.isRegularFile == true, v.isSymbolicLink != true, let size=v.fileSize, (1...536_870_912).contains(size) else { throw Failure.invalidAudio }
        let asset=AVURLAsset(url:source), duration=try await asset.load(.duration).seconds
        guard duration.isFinite, (3...1800).contains(duration) else { throw Failure.resourceBound }
        let tracks=try await asset.loadTracks(withMediaType:.audio)
        guard tracks.count==1,let track=tracks.first else { throw Failure.invalidAudio }
        let reader=try AVAssetReader(asset:asset)
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[AVFormatIDKey:kAudioFormatLinearPCM,AVSampleRateKey:16_000,AVNumberOfChannelsKey:1,AVLinearPCMBitDepthKey:32,AVLinearPCMIsFloatKey:true,AVLinearPCMIsBigEndianKey:false,AVLinearPCMIsNonInterleaved:false])
        output.alwaysCopiesSampleData=false
        guard reader.canAdd(output) else { throw Failure.invalidAudio };reader.add(output)
        guard reader.startReading() else { throw Failure.invalidAudio }
        defer { if reader.status == .reading { reader.cancelReading() } }
        var samples:[Float]=[]; samples.reserveCapacity(min(28_800_000,Int(duration*16_000)+16_000));var last=Date()
        while let buffer=output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let description=CMSampleBufferGetFormatDescription(buffer),let format=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,format.mSampleRate==16_000,format.mChannelsPerFrame==1,format.mBitsPerChannel==32,format.mFormatFlags & kAudioFormatFlagIsFloat != 0,format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,let block=CMSampleBufferGetDataBuffer(buffer) else { throw Failure.invalidAudio }
            // Do not silently map a discontinuous or offset audio timeline to
            // different video timestamps. Small codec priming offsets fit inside
            // the 150 ms reference boundary padding; larger gaps fail closed.
            let timestamp = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            guard timestamp.isFinite, abs(timestamp - Double(samples.count)/16_000) <= 0.05 else { throw Failure.invalidTimeline }
            let count=CMBlockBufferGetDataLength(block)
            guard count>0,count<=4_194_304,count%4==0,count/4<=28_800_000-samples.count else { throw Failure.resourceBound }
            var bytes=Data(count:count)
            let status=bytes.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:count,destination:$0.baseAddress!) }
            guard status==kCMBlockBufferNoErr else { throw Failure.invalidAudio }
            let chunk:[Float]=bytes.withUnsafeBytes { raw in (0..<count/4).map { Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:$0*4,as:UInt32.self))) } }
            guard chunk.allSatisfy({ $0.isFinite && abs($0)<=1.01 }) else { throw Failure.invalidAudio }
            samples.append(contentsOf:chunk)
            if Date().timeIntervalSince(last)>=1 { last=Date();progress("Decoded \(Int(Double(samples.count)/16_000)) of \(Int(duration)) seconds for speaker analysis.") }
        }
        guard reader.status == .completed,samples.count>=48_000 else { throw Failure.invalidAudio }
        return samples
    }
}
