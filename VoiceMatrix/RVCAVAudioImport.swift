#if os(iOS)
import Foundation
import AVFoundation

/// Apple media decoding/resampling remains device-unverified.
/// Output is a private 16 kHz mono PCM16 WAV accepted by the portable workflow.
enum RVCAVAudioImport {
    static func decode(input:URL,output:URL) throws {
        guard !FileManager.default.fileExists(atPath:output.path) else {throw RVCFileError.destination}
        let source=try AVAudioFile(forReading:input,commonFormat:.pcmFormatFloat32,interleaved:false)
        let format=source.processingFormat
        guard format.sampleRate.isFinite,(8000...192000).contains(format.sampleRate),
              (1...2).contains(format.channelCount),source.length>0,
              Double(source.length)/format.sampleRate<=7200,
              let targetFormat=AVAudioFormat(commonFormat:.pcmFormatInt16,sampleRate:16000,channels:1,interleaved:true),
              let converter=AVAudioConverter(from:format,to:targetFormat),
              let inputBuffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:8192),
              let outputBuffer=AVAudioPCMBuffer(pcmFormat:targetFormat,frameCapacity:8192) else {throw RVCFileError.format}
        converter.downmix=true
        var target:AVAudioFile?=try AVAudioFile(forWriting:output,settings:targetFormat.settings,commonFormat:.pcmFormatInt16,interleaved:true)
        defer {target=nil}
        var inputError:Error?;var count=0;var empty=0
        while true {
            try Task.checkCancellation()
            var conversionError:NSError?
            let status=converter.convert(to:outputBuffer,error:&conversionError) {requested,state in
                if Task.isCancelled {state.pointee = .endOfStream;return nil}
                do {
                    try source.read(into:inputBuffer,frameCount:min(requested,inputBuffer.frameCapacity))
                    if inputBuffer.frameLength==0 {state.pointee = .endOfStream;return nil}
                    state.pointee = .haveData
                    return inputBuffer
                } catch {inputError=error;state.pointee = .endOfStream;return nil}
            }
            try Task.checkCancellation()
            if let inputError {throw inputError}
            if let conversionError {throw conversionError}
            if status == .error {throw RVCFileError.format}
            count += Int(outputBuffer.frameLength)
            guard count<=115200000 else {throw RVCFileError.bounds}
            if outputBuffer.frameLength>0 {try target!.write(from:outputBuffer);empty=0}
            else {empty += 1}
            if status == .endOfStream {break}
            guard empty<3 else {throw RVCFileError.format}
        }
        guard count>=960 else {throw RVCFileError.bounds}
    }
}
#endif
