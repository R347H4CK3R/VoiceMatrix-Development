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
        var channels:Int?
        for description in descriptions {
            guard let format=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                  format.mSampleRate.isFinite,(8000...192000).contains(format.mSampleRate),
                  format.mChannelsPerFrame==1 || format.mChannelsPerFrame==2 else {throw Failure.unsupportedAudio}
            let count=Int(format.mChannelsPerFrame)
            if let channels,channels != count {throw Failure.unsupportedAudio}
            channels=count
        }
        guard let channels else {throw Failure.unsupportedAudio}
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
        reader.timeRange=CMTimeRange(start:CMTime(value:startFrame,timescale:Int32(rate)),
                                     duration:CMTime(value:Int64(wantedFrames),timescale:Int32(rate)))
        let output=AVAssetReaderTrackOutput(track:track,outputSettings:[
            AVFormatIDKey:kAudioFormatLinearPCM,
            AVSampleRateKey:rate,
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
        var samples:[Float]=[]
        samples.reserveCapacity(wantedFrames*2)
        var decodedFrames=0,previousPTS:Double?,bufferIndex=0
        while let sample=output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard CMSampleBufferDataIsReady(sample),
                  let description=CMSampleBufferGetFormatDescription(sample),
                  let format=CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
                  format.mFormatID==kAudioFormatLinearPCM,format.mSampleRate==Double(rate),
                  format.mChannelsPerFrame==UInt32(channels),format.mBitsPerChannel==32,
                  format.mBytesPerFrame==UInt32(channels*4),
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
                  format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                  let block=CMSampleBufferGetDataBuffer(sample) else {throw Failure.invalidPCM}
            let frameCount=CMSampleBufferGetNumSamples(sample)
            let bytes=CMBlockBufferGetDataLength(block)
            guard frameCount>0,frameCount<=maximumFrames,
                  bytes==frameCount*channels*4,
                  decodedFrames+frameCount<=min(maximumFrames,wantedFrames+1) else {throw Failure.bounds}
            let pts=CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let sampleDuration=CMSampleBufferGetDuration(sample).seconds
            let expectedPTS=selectedStart+Double(decodedFrames)/Double(rate)
            if bufferIndex<4 {diagnostic("clip buffer=\(bufferIndex) frames=\(frameCount) pts=\(pts) expectedPTS=\(expectedPTS) duration=\(sampleDuration)")}
            bufferIndex += 1
            guard pts.isFinite,abs(pts-expectedPTS)<=sampleTolerance,
                  sampleDuration.isFinite,sampleDuration>0,
                  abs(sampleDuration-Double(frameCount)/Double(rate))<=sampleTolerance else {throw Failure.invalidTimeline}
            if let previousPTS,pts<=previousPTS {throw Failure.invalidTimeline}
            previousPTS=pts
            var data=Data(count:bytes)
            let status=data.withUnsafeMutableBytes {buffer in
                CMBlockBufferCopyDataBytes(block,atOffset:0,dataLength:bytes,destination:buffer.baseAddress!)
            }
            guard status==kCMBlockBufferNoErr else {throw Failure.unreadable}
            try data.withUnsafeBytes {raw in
                for frame in 0..<frameCount {
                    if frame%4096==0 {try Task.checkCancellation()}
                    let offset=frame*channels*4
                    let left=Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:offset,as:UInt32.self)))
                    let right=channels==1 ? left : Float(bitPattern:UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:offset+4,as:UInt32.self)))
                    guard left.isFinite,right.isFinite else {throw Failure.invalidPCM}
                    samples.append(left);samples.append(right)
                }
            }
            decodedFrames += frameCount
        }
        try Task.checkCancellation()
        diagnostic("clip readerStatus=\(reader.status.rawValue) decodedFrames=\(decodedFrames) wantedFrames=\(wantedFrames)")
        guard reader.status == .completed else {throw Failure.unreadable}
        // Resampling endpoint rounding may differ by one frame. Never synthesize a
        // frame or discard decoded data to make this check pass; report actual count.
        guard decodedFrames>0,abs(decodedFrames-wantedFrames)<=1,
              samples.count==decodedFrames*2 else {throw Failure.invalidTimeline}
        return Clip(samples:samples,frames:decodedFrames,sampleRate:rate,start:selectedStart)
    }
}
