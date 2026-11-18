#if canImport(AVFoundation)
import Foundation
import AVFoundation

enum SeparationAudioImport {
    struct Audio {let left:[Float];let right:[Float]}
    /// Whole-file conversion only. No channel averaging, prefix clipping or silent trim.
    static func decode(_ url:URL) throws -> Audio {
        let source=try AVAudioFile(forReading:url,commonFormat:.pcmFormatFloat32,interleaved:false)
        let format=source.processingFormat, rate=format.sampleRate, channels=format.channelCount
        guard rate.isFinite,(8000...192000).contains(rate),(1...2).contains(channels),source.length>0,
              Double(source.length)/rate<=10,
              let stereo=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:2,interleaved:false),
              let target=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:44100,channels:2,interleaved:false),
              let original=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:8192),
              let input=AVAudioPCMBuffer(pcmFormat:stereo,frameCapacity:8192),
              let output=AVAudioPCMBuffer(pcmFormat:target,frameCapacity:8192),
              let converter=AVAudioConverter(from:stereo,to:target) else {throw SeparationStore.Failure.invalid}
        converter.primeMethod = .none
        var left:[Float]=[],right:[Float]=[],readError:Error?,empty=0,consumed:Int64=0
        while true {
            try Task.checkCancellation()
            var error:NSError?
            let status=converter.convert(to:output,error:&error) {requested,state in
                do {
                    try Task.checkCancellation()
                    try source.read(into:original,frameCount:min(requested,8192))
                    guard original.frameLength>0 else {state.pointee = .endOfStream;return nil}
                    guard let from=original.floatChannelData,let to=input.floatChannelData else {throw SeparationStore.Failure.invalid}
                    consumed += Int64(original.frameLength)
                    guard consumed<=source.length else {throw SeparationStore.Failure.bounds}
                    input.frameLength=original.frameLength
                    for i in 0..<Int(original.frameLength) {
                        let l=from[0][i],r=from[channels==1 ? 0:1][i]
                        guard l.isFinite,r.isFinite,abs(l)<=1,abs(r)<=1 else {throw SeparationStore.Failure.invalid}
                        to[0][i]=l;to[1][i]=r
                    }
                    state.pointee = .haveData;return input
                } catch {readError=error;state.pointee = .endOfStream;return nil}
            }
            try Task.checkCancellation()
            if let readError {throw readError};if let error {throw error}
            guard status != .error,let data=output.floatChannelData else {throw SeparationStore.Failure.invalid}
            let count=Int(output.frameLength)
            guard left.count+count<=441000 else {throw SeparationStore.Failure.bounds}
            for i in 0..<count {
                guard data[0][i].isFinite,data[1][i].isFinite,abs(data[0][i])<=1,abs(data[1][i])<=1 else {throw SeparationStore.Failure.invalid}
                left.append(data[0][i]);right.append(data[1][i])
            }
            empty=count==0 ? empty+1:0
            if status == .endOfStream {break}
            guard empty<3 else {throw SeparationStore.Failure.invalid}
        }
        let expected=Int((Double(source.length)*44100/rate).rounded())
        guard consumed==source.length,!left.isEmpty,left.count==expected else {throw SeparationStore.Failure.invalid}
        return Audio(left:left,right:right)
    }
}
#endif
