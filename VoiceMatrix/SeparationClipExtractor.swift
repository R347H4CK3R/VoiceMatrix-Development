import Foundation
import AVFoundation
import CoreMedia

/// Reads only an app-owned, hash-verified retained-media snapshot supplied by the caller.
/// This selects a reviewed interval; it does not separate sources or authenticate voices.
enum SeparationClipExtractor {
    enum Failure:Error {case localFileRequired,bounds,unreadable,unsupportedAudio,invalidTimeline,invalidPCM}
    struct Clip:Sendable {
        let samples:[Float] // Interleaved stereo; mono is explicitly duplicated.
        let frames:Int
        let sampleRate:Int
        let start:Double
        var seconds:Double {Double(frames)/Double(sampleRate)}
    }
    private static let rate=44_100
    private static let maximumFrames=441_000
    private static let sampleTolerance=1.0/44_100.0+1e-9

    /// Shared explicit edit-timeline policy. The first covering segment may begin
    /// before the selection; subsequent segments may not overlap preceding media.
    static func validateCoverage(_ intervals:[(start:Double,end:Double)],start:Double,end:Double) throws {
        guard start.isFinite,end.isFinite,end>start else {throw Failure.invalidTimeline}
        var cursor=start,previousEnd:Double?
        for segment in intervals.sorted(by:{$0.start<$1.start}) {
            guard segment.start.isFinite,segment.end.isFinite,segment.end>=segment.start,
                  segment.start<=cursor+sampleTolerance else {throw Failure.invalidTimeline}
            if let previousEnd,segment.start<previousEnd-sampleTolerance {throw Failure.invalidTimeline}
            previousEnd=segment.end
            cursor=max(cursor,segment.end)
        }
        guard cursor>=end-sampleTolerance else {throw Failure.invalidTimeline}
    }

    static func extract(source:URL,start:Double,seconds:Double,diagnostic:@Sendable (String)->Void = {_ in}) async throws -> Clip {
        try Task.checkCancellation()
        guard source.isFileURL else {throw Failure.localFileRequired}
        guard start.isFinite,seconds.isFinite,start>=0,(0.5...10).contains(seconds),
              start+seconds<=1800 else {throw Failure.bounds}
        let values=try source.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard values.isRegularFile==true,values.isSymbolicLink != true,
              let size=values.fileSize,size>0,size<=536_870_912 else {throw Failure.unreadable}
        // Quantization is explicit: nearest 44.1 kHz sample (at most half a sample).
        let startFrame=Int64((start*Double(rate)).rounded())
        let wantedFrames=Int((seconds*Double(rate)).rounded())
        guard wantedFrames>=22_050,wantedFrames<=maximumFrames else {throw Failure.bounds}
        let selectedStart=Double(startFrame)/Double(rate)
        let selectedEnd=selectedStart+Double(wantedFrames)/Double(rate)
        guard selectedEnd<=1800 else {throw Failure.bounds}
        // Only bytes inside the verified snapshot may be decoded, never external
        // MOV data references (local files or remote resources).
        let asset=AVURLAsset(url:source,options:[
            AVURLAssetReferenceRestrictionsKey:NSNumber(value:AVAssetReferenceRestrictions.forbidAll.rawValue)
        ])
        let duration=try await asset.load(.duration).seconds
        guard duration.isFinite,duration>0,duration<=1800,
              selectedEnd<=duration+sampleTolerance else {throw Failure.bounds}
        let tracks=try await asset.loadTracks(withMediaType:.audio)
        guard tracks.count==1,let track=tracks.first else {throw Failure.unsupportedAudio}
        let descriptions=try await track.load(.formatDescriptions)
        guard !descriptions.isEmpty else {throw Failure.unsupportedAudio}
        var channels:Int?, nativeRate:Double?
        for description in descriptions {
            guard let format=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                  format.mSampleRate.isFinite,(8000...192000).contains(format.mSampleRate),
                  format.mChannelsPerFrame==1 || format.mChannelsPerFrame==2 else {throw Failure.unsupportedAudio}
            let count=Int(format.mChannelsPerFrame)
            if let channels,channels != count {throw Failure.unsupportedAudio}
            if let nativeRate,nativeRate != format.mSampleRate {throw Failure.unsupportedAudio}
            nativeRate=format.mSampleRate
            channels=count
        }
        guard let channels,let nativeRate else {throw Failure.unsupportedAudio}
        let range=try await track.load(.timeRange)
        let trackStart=range.start.seconds,trackEnd=CMTimeRangeGetEnd(range).seconds
        diagnostic("clip channels=\(channels) selectedStart=\(selectedStart) selectedEnd=\(selectedEnd) trackStart=\(trackStart) trackEnd=\(trackEnd)")
        guard trackStart.isFinite,trackEnd.isFinite,trackEnd>trackStart,
              selectedStart>=trackStart-sampleTolerance,selectedEnd<=trackEnd+sampleTolerance else {throw Failure.invalidTimeline}
        // An empty edit can decode as perfectly timestamped silence. Reject its actual
        // intersection, not merely long gaps, before starting the PCM reader.
        let segments=try await track.load(.segments)
        var coverage:[(start:Double,end:Double)]=[]
        for segment in segments {
            let target=segment.timeMapping.target
            let a=target.start.seconds,b=CMTimeRangeGetEnd(target).seconds
            guard a.isFinite,b.isFinite,b>=a else {throw Failure.invalidTimeline}
            if min(selectedEnd,b)-max(selectedStart,a)>1e-9 {
                guard !segment.isEmpty else {throw Failure.invalidTimeline}
                coverage.append((a,b))
            }
        }
        if !segments.isEmpty {try validateCoverage(coverage,start:selectedStart,end:selectedEnd)}
        try Task.checkCancellation()
        let reader=try AVAssetReader(asset:asset)
        // Do not set timeRange. Seeking restarts AAC/resampler state; a finite
        // requested range can also omit converter tail frames. Decode from the
        // real stream beginning and retain only timestamp-mapped selected frames.
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[
            AVFormatIDKey:kAudioFormatLinearPCM,
            AVSampleRateKey:nativeRate,
            AVNumberOfChannelsKey:channels,
            AVLinearPCMBitDepthKey:32,
            AVLinearPCMIsFloatKey:true,
            AVLinearPCMIsBigEndianKey:false,
            AVLinearPCMIsNonInterleaved:false
        ])
        output.alwaysCopiesSampleData=false
        guard reader.canAdd(output) else {throw Failure.unsupportedAudio}
        reader.add(output)
        guard reader.startReading() else {throw Failure.unreadable}
        defer {if reader.status == .reading {reader.cancelReading()}}
        // AVAssetReader decodes at the source rate only. Explicit conversion owns
        // priming and EOF draining; reader-side resampling loses tail frames on
        // some PCM sources. See Apple TN3136, streaming conversion input protocol.
        guard let nativeFormat=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:nativeRate,channels:2,interleaved:false),
              let targetFormat=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:Double(rate),channels:2,interleaved:false),
              let input=AVAudioPCMBuffer(pcmFormat:nativeFormat,frameCapacity:8192),
              let converted=AVAudioPCMBuffer(pcmFormat:targetFormat,frameCapacity:8192),
              let converter=AVAudioConverter(from:nativeFormat,to:targetFormat) else {throw Failure.unsupportedAudio}
        converter.primeMethod = .normal
        var samples:[Float]=[]
        samples.reserveCapacity(wantedFrames*2)
        var nativeFrames=0,convertedFrames=0,bufferIndex=0,conversionIndex=0,empty=0
        var previousPTS:Double?,originPTS:Double?,originFrame:Int64?
        var pending=Data(),pendingOffset=0,pendingFrames=0
        var readerEOF=false,intervalComplete=false,converterEOF=false
        var inputError:Error?
        let selectedEndFrame=startFrame+Int64(wantedFrames)
        let nativeTolerance=1.0/nativeRate+1e-9

        func readNativeBuffer() throws -> Bool {
            try Task.checkCancellation()
            guard let sample=output.copyNextSampleBuffer() else {
                guard reader.status == .completed else {throw Failure.unreadable}
                readerEOF=true
                return false
            }
            guard CMSampleBufferDataIsReady(sample),
                  let description=CMSampleBufferGetFormatDescription(sample),
                  let format=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                  format.mFormatID==kAudioFormatLinearPCM,format.mSampleRate==nativeRate,
                  format.mChannelsPerFrame==UInt32(channels),format.mBitsPerChannel==32,
                  format.mBytesPerFrame==UInt32(channels*4),
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                  let block=CMSampleBufferGetDataBuffer(sample) else {throw Failure.invalidPCM}
            let count=CMSampleBufferGetNumSamples(sample)
            let bytes=CMBlockBufferGetDataLength(block)
            guard count>0,count<=1_048_576,bytes==count*channels*4,
                  Double(nativeFrames+count)<=1800*nativeRate+1,bufferIndex<1_000_000 else {throw Failure.bounds}
            let pts=CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let duration=CMSampleBufferGetDuration(sample).seconds
            guard pts.isFinite,pts>=(-nativeTolerance),pts<=1800 else {throw Failure.invalidTimeline}
            if originPTS==nil {
                originPTS=pts
                originFrame=Int64((pts*Double(rate)).rounded())
                guard let originFrame,originFrame<=startFrame else {throw Failure.invalidTimeline}
            }
            guard let originPTS else {throw Failure.invalidTimeline}
            let expected=originPTS+Double(nativeFrames)/nativeRate
            if bufferIndex<4 {diagnostic("clip nativeBuffer=\(bufferIndex) frames=\(count) pts=\(pts) expectedPTS=\(expected) duration=\(duration)")}
            guard abs(pts-expected)<=nativeTolerance,duration.isFinite,duration>0,
                  abs(duration-Double(count)/nativeRate)<=nativeTolerance else {throw Failure.invalidTimeline}
            if let previousPTS,pts<=previousPTS {throw Failure.invalidTimeline}
            previousPTS=pts
            pending=Data(count:bytes)
            let copyStatus=pending.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:bytes,destination:$0.baseAddress!)
            }
            guard copyStatus==kCMBlockBufferNoErr else {throw Failure.unreadable}
            pendingOffset=0;pendingFrames=count
            nativeFrames += count;bufferIndex += 1
            return true
        }
        while true {
            try Task.checkCancellation()
            guard conversionIndex<1_000_000 else {throw Failure.bounds}
            conversionIndex += 1
            converted.frameLength=0
            var conversionError:NSError?
            let status=converter.convert(to:converted,error:&conversionError) {requested,state in
                do {
                    try Task.checkCancellation()
                    if pendingOffset==pendingFrames {
                        if readerEOF {state.pointee = .endOfStream;return nil}
                        guard try readNativeBuffer() else {state.pointee = .endOfStream;return nil}
                    }
                    guard requested>0,let destination=input.floatChannelData else {throw Failure.invalidPCM}
                    let count=min(Int(requested),8192,pendingFrames-pendingOffset)
                    guard count>0 else {throw Failure.invalidPCM}
                    input.frameLength=AVAudioFrameCount(count)
                    try pending.withUnsafeBytes {raw in
                        for frame in 0..<count {
                            if frame%4096==0 {try Task.checkCancellation()}
                            for channel in 0..<2 {
                                let sourceChannel=channels==1 ? 0:channel
                                let offset=((pendingOffset+frame)*channels+sourceChannel)*4
                                let value=Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:offset,as:UInt32.self)))
                                guard value.isFinite else {throw Failure.invalidPCM}
                                destination[channel][frame]=value
                            }
                        }
                    }
                    pendingOffset += count
                    state.pointee = .haveData
                    return input
                } catch {
                    inputError=error
                    // This status is not EOF authorization: the captured error is
                    // rethrown before any converter output can be retained.
                    state.pointee = .noDataNow
                    return nil
                }
            }
            try Task.checkCancellation()
            if let inputError {throw inputError}
            guard conversionError==nil,status != .error,
                  reader.status != .failed,reader.status != .cancelled,
                  let pcm=converted.floatChannelData else {throw Failure.unreadable}
            let count=Int(converted.frameLength)
            guard count<=8192,convertedFrames+count<=1800*rate+8192 else {throw Failure.bounds}
            if count>0 {
                guard let originFrame else {throw Failure.invalidTimeline}
                let bufferStart=originFrame+Int64(convertedFrames)
                let keepStart=max(bufferStart,startFrame)
                let keepEnd=min(bufferStart+Int64(count),selectedEndFrame)
                if keepEnd>keepStart {
                    guard keepStart==startFrame+Int64(samples.count/2) else {throw Failure.invalidTimeline}
                    for frame in Int(keepStart-bufferStart)..<Int(keepEnd-bufferStart) {
                        if frame%4096==0 {try Task.checkCancellation()}
                        let left=pcm[0][frame],right=pcm[1][frame]
                        guard left.isFinite,right.isFinite else {throw Failure.invalidPCM}
                        samples.append(left);samples.append(right)
                    }
                }
            }
            convertedFrames += count
            empty=count==0 ? empty+1:0
            if samples.count==wantedFrames*2 {
                try Task.checkCancellation()
                intervalComplete=true
                if reader.status == .reading {reader.cancelReading()}
                break
            }
            if status == .endOfStream {
                guard readerEOF,pendingOffset==pendingFrames else {throw Failure.unreadable}
                converterEOF=true
                break
            }
            guard empty<3 else {throw Failure.invalidPCM}
        }
        try Task.checkCancellation()
        let retainedFrames=samples.count/2
        diagnostic("clip nativeRate=\(nativeRate) nativeFrames=\(nativeFrames) convertedFrames=\(convertedFrames) readerEOF=\(readerEOF) converterEOF=\(converterEOF) retainedFrames=\(retainedFrames) wantedFrames=\(wantedFrames) intervalComplete=\(intervalComplete)")
        guard intervalComplete || converterEOF else {throw Failure.unreadable}
        // Only actual converted samples are returned; never synthesize a missing
        // endpoint. Preserve the original at-most-one-frame rounding allowance.
        guard retainedFrames>0,wantedFrames-retainedFrames<=1,
              samples.count==retainedFrames*2 else {throw Failure.invalidTimeline}
        return Clip(samples:samples,frames:retainedFrames,sampleRate:rate,start:selectedStart)
    }
}
