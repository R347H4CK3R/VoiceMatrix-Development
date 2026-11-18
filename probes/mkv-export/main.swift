import Foundation
import AVFoundation
import AudioToolbox

@main struct Probe {
    static func markerPolicy() throws {
        func marker(pts: CMTime = .zero, duration: CMTime = .zero) throws -> CMSampleBuffer {
            var timing = CMSampleTimingInfo(duration:duration,presentationTimeStamp:pts,decodeTimeStamp:.invalid)
            var result: CMSampleBuffer?
            let status = CMSampleBufferCreate(allocator:kCFAllocatorDefault,dataBuffer:nil,dataReady:true,
                makeDataReadyCallback:nil,refcon:nil,formatDescription:nil,sampleCount:0,
                sampleTimingEntryCount:1,sampleTimingArray:&timing,sampleSizeEntryCount:0,sampleSizeArray:nil,sampleBufferOut:&result)
            guard status == 0, let result else { fatalError("Cannot construct marker: \(status)") }
            CMSetAttachment(result,key:kCMSampleBufferAttachmentKey_EmptyMedia,value:kCFBooleanTrue,attachmentMode:kCMAttachmentMode_ShouldPropagate)
            return result
        }
        let empty = try marker()
        precondition(LocalMKVExport.isInitialEmptyMarker(empty),"Initial zero-duration empty marker must be recognized")
        CMRemoveAttachment(empty,key:kCMSampleBufferAttachmentKey_EmptyMedia)
        precondition(!LocalMKVExport.isInitialEmptyMarker(empty),"Unmarked empty sample must not be ignored")
        let permanent = try marker()
        CMSetAttachment(permanent,key:kCMSampleBufferAttachmentKey_PermanentEmptyMedia,value:kCFBooleanTrue,attachmentMode:kCMAttachmentMode_ShouldPropagate)
        precondition(!LocalMKVExport.isInitialEmptyMarker(permanent),"Permanent empty media must not be ignored")
        let later = try marker(pts:CMTime(value:1,timescale:1))
        precondition(!LocalMKVExport.isInitialEmptyMarker(later),"Later edit must not be ignored")
        print("EMPTY_MARKER_POLICY_PASSED only explicit initial zero-duration empty edit recognized")
    }
    static func aacPolicy() throws {
        let lc = Data([0x11,0x88]) // AAC-LC 48 kHz mono, 1024-frame packets.
        for flags in [UInt32(0),UInt32(2)] {
            try LocalMKVExport.validateAACConfiguration(lc,sampleRate:48000,channels:1,formatFlags:flags,framesPerPacket:1024)
            try LocalMKVExport.validateAACConfiguration(lc + Data([0x56,0xe5,0x00]),sampleRate:48000,channels:1,formatFlags:flags,framesPerPacket:1024)
        }
        let invalid: [(Data, UInt32, UInt32, UInt32)] = [
            (lc,5,1024,1), (lc,2,960,1), (lc,0,1024,2),
            (Data([0x29,0x88]),0,1024,1), (Data(),0,1024,1),
            (lc + Data([0x56,0xe5,0x80]),0,1024,1)]
        for (config,flags,frames,channels) in invalid {
            var rejected = false
            do { try LocalMKVExport.validateAACConfiguration(config,sampleRate:48000,channels:channels,formatFlags:flags,framesPerPacket:frames) }
            catch { rejected = true }
            guard rejected else { fatalError("Unsupported AAC configuration was accepted") }
        }
        print("AAC_POLICY_PASSED unspecified flags require exact LC config; contradictory/HE/960-frame configurations rejected")
    }
    /// Synthetic-fixture diagnostics only: expose each guard input before attempting export.
    static func evidence(_ input: URL) async throws {
        let asset = AVURLAsset(url:input)
        for media in [AVMediaType.video, .audio] {
            for track in try await asset.loadTracks(withMediaType:media) {
                for format in try await track.load(.formatDescriptions) {
                    var item: [String:Any] = ["media":media.rawValue,"subtype":CMFormatDescriptionGetMediaSubType(format)]
                    if media == .audio, let a = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        item["formatID"] = a.mFormatID; item["flags"] = a.mFormatFlags
                        item["framesPerPacket"] = a.mFramesPerPacket; item["channels"] = a.mChannelsPerFrame; item["sampleRate"] = a.mSampleRate
                        var size = 0
                        if let pointer = CMAudioFormatDescriptionGetMagicCookie(format,sizeOut:&size), size <= 65536 {
                            item["cookieHex"] = Data(bytes:pointer,count:size).map { String(format:"%02x",$0) }.joined()
                        }
                    }
                    if let atoms = CMFormatDescriptionGetExtension(format,extensionKey:kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms) as? [String:Any] {
                        item["atomKeys"] = atoms.keys.sorted()
                        if let esds = atoms["esds"] as? Data { item["esdsHex"] = esds.map { String(format:"%02x",$0) }.joined() }
                    }
                    let line = try JSONSerialization.data(withJSONObject:item,options:[.sortedKeys])
                    FileHandle.standardError.write(Data("MKV_SOURCE_FORMAT ".utf8) + line + Data([10]))
                }
            }
        }
    }
    /// Bounded metadata-only diagnostics. Never prints attachment strings/URLs or payloads.
    static func sampleStructureEvidence(_ sample: CMSampleBuffer) -> String {
        let keys: [CFString] = [kCMSampleBufferAttachmentKey_EmptyMedia,
            kCMSampleBufferAttachmentKey_PermanentEmptyMedia,
            kCMSampleBufferAttachmentKey_DisplayEmptyMediaImmediately,
            kCMSampleBufferAttachmentKey_TrimDurationAtStart,
            kCMSampleBufferAttachmentKey_TrimDurationAtEnd,
            kCMSampleBufferAttachmentKey_SampleReferenceURL,
            kCMSampleBufferAttachmentKey_SampleReferenceByteOffset,
            kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding,
            kCMSampleBufferAttachmentKey_DrainAfterDecoding,
            kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration,
            kCMSampleBufferAttachmentKey_TransitionID,
            kCMSampleBufferAttachmentKey_ResumeOutput,
            kCMSampleBufferAttachmentKey_FillDiscontinuitiesWithSilence,
            kCMSampleBufferAttachmentKey_DroppedFrameReason,
            kCMSampleBufferAttachmentKey_DroppedFrameReasonInfo,
            kCMSampleBufferAttachmentKey_PostNotificationWhenConsumed]
        let attachments = keys.map { key -> String in
            guard let value = CMGetAttachment(sample,key:key,attachmentModeOut:nil) else { return "\(key)=absent" }
            let type = CFGetTypeID(value)
            if type == CFBooleanGetTypeID() { return "\(key)=bool:\(String(describing:value as? Bool))" }
            if type == CFNumberGetTypeID() { return "\(key)=number:\(String(describing:value as? NSNumber))" }
            return "\(key)=present,type:\(type)"
        }.joined(separator:";")
        let entries = CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:false) as? [[String:Any]]
        let perSampleKeys = [kCMSampleAttachmentKey_NotSync,kCMSampleAttachmentKey_DependsOnOthers,
            kCMSampleAttachmentKey_IsDependedOnByOthers,kCMSampleAttachmentKey_PartialSync].map { $0 as String }
        let firstKeys = perSampleKeys.filter { entries?.first?[$0] != nil }.joined(separator:",")
        return "valid=\(CMSampleBufferIsValid(sample)),ready=\(CMSampleBufferDataIsReady(sample)),image=\(CMSampleBufferGetImageBuffer(sample) != nil),sampleAttachmentCount=\(entries?.count ?? 0),firstSampleKeys=[\(firstKeys)],attachments={\(attachments)}"
    }
    /// Diagnostic-only bounded experiment. No exported media or admission rules change.
    /// Compare independent vs interleaved readers and copy ownership to isolate API setup.
    static func readerEvidence(_ input: URL) async throws {
        for copies in [false,true] {
            for combined in [false,true] {
                let asset = AVURLAsset(url:input)
                let video = try await asset.loadTracks(withMediaType:.video)
                let audio = try await asset.loadTracks(withMediaType:.audio)
                let groups = combined ? [video + audio] : [video,audio]
                for tracks in groups where !tracks.isEmpty {
                    let reader = try AVAssetReader(asset:asset)
                    let outputs = tracks.map { AVAssetReaderTrackOutput(track:$0,outputSettings:nil) }
                    for output in outputs { output.alwaysCopiesSampleData = copies; reader.add(output) }
                    guard reader.startReading() else { throw reader.error ?? NSError(domain:"probe-reader",code:1) }
                    for round in 0..<3 {
                        for (index,output) in outputs.enumerated() {
                            guard let sample = output.copyNextSampleBuffer() else { continue }
                            let structure = sampleStructureEvidence(sample)
                            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                            let bytes = CMSampleBufferGetDataBuffer(sample).map { CMBlockBufferGetDataLength($0) } ?? -1
                            let line = "MKV_READER_EXPERIMENT copies=\(copies),combined=\(combined),track=\(index),round=\(round),samples=\(CMSampleBufferGetNumSamples(sample)),pts=\(pts.value)/\(pts.timescale),bytes=\(bytes),status=\(reader.status.rawValue),errorCode=\((reader.error as NSError?)?.code ?? 0),\(structure)\n"
                            FileHandle.standardError.write(Data(line.utf8))
                        }
                    }
                    reader.cancelReading()
                }
            }
        }
    }
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 2 && args[1] == "--aac-policy" { try aacPolicy(); try markerPolicy(); return }
        guard args.count == 3 || args.count == 4 else { fatalError("input.mp4 output.mkv") }
        let input = URL(fileURLWithPath: args[1])
        try await evidence(input)
        try await readerEvidence(input)
        if args.count == 4 && args[3] == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
        _ = try await LocalMKVExport.export(input: input, destination: URL(fileURLWithPath: args[2]), maxBytes: args.count == 4 ? (Int64(args[3]) ?? 536_870_912) : 536_870_912) { _ in }
    }
}
