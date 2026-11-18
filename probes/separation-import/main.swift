import Foundation
import AVFoundation
import Darwin

struct ProbeFailure:Error,CustomStringConvertible {
    let description:String
}
func stage<T>(_ label:String,_ body:() throws -> T) throws -> T {
    FileHandle.standardError.write(Data(("BEGIN "+label+"\n").utf8))
    do {let result=try body();FileHandle.standardError.write(Data(("PASS "+label+"\n").utf8));return result}
    catch {throw ProbeFailure(description:label+": "+String(reflecting:error))}
}
func run() throws {
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
func fixture(_ name:String,rate:Double,channels:AVAudioChannelCount,frames:AVAudioFrameCount,impulses:Bool=false) throws -> URL {
    let url=root.appendingPathComponent(name+".wav")
    let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:channels,interleaved:false)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frames)!
    buffer.frameLength=frames
    for c in 0..<Int(channels) {for i in 0..<Int(frames) {
        buffer.floatChannelData![c][i]=impulses ? 0 : (c==0 ? 0.125 : -0.25)
    }}
    if impulses {
        buffer.floatChannelData![0][0]=0.5
        buffer.floatChannelData![0][Int(frames)-1]=0.5
        buffer.floatChannelData![1][Int(frames)/2] = -0.5
    }
    // WAV storage is interleaved; the AVAudioPCMBuffer processing format is planar.
    // Never pass AVLinearPCMIsNonInterleaved=true as the on-disk WAV settings.
    let disk=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:channels,interleaved:true)!
    var file:AVAudioFile?=try stage(name+" create interleaved WAV") {
        try AVAudioFile(forWriting:url,settings:disk.settings,commonFormat:.pcmFormatFloat32,interleaved:false)
    }
    try stage(name+" write planar processing buffer") {try file!.write(from:buffer)}
    file=nil
    return url
}
let stereo=try fixture("stereo",rate:44100,channels:2,frames:4410)
let before=try Data(contentsOf:stereo)
let a=try stage("stereo decode") {try SeparationAudioImport.decode(stereo)}
precondition(a.left.count==4410 && a.right.count==4410)
precondition(a.left.allSatisfy{$0==0.125} && a.right.allSatisfy{$0 == -0.25})
let after=try Data(contentsOf:stereo);precondition(before==after)
let mono=try fixture("mono",rate:44100,channels:1,frames:4410)
let b=try stage("mono decode") {try SeparationAudioImport.decode(mono)}
precondition(b.left==b.right && b.left.count==4410)
let resampled=try fixture("resample",rate:48000,channels:2,frames:4800)
let c=try stage("resampled decode") {try SeparationAudioImport.decode(resampled)}
precondition(c.left.count==4410 && c.right.count==4410)
let impulseURL=try fixture("boundary-impulses",rate:48000,channels:2,frames:4800,impulses:true)
let impulseBefore=try Data(contentsOf:impulseURL)
let impulse=try stage("resampled first last and midpoint impulses") {try SeparationAudioImport.decode(impulseURL)}
precondition(impulse.left.count==4410 && impulse.right.count==4410)
func peak(_ samples:[Float],_ range:Range<Int>)->Int {range.max{abs(samples[$0])<abs(samples[$1])}!}
let first=peak(impulse.left,0..<128),last=peak(impulse.left,4282..<4410),middle=peak(impulse.right,0..<4410)
FileHandle.standardError.write(Data("impulse peaks: first=\(first), last=\(last), middle=\(middle)\n".utf8))
precondition(first<=1 && abs(last-4409)<=1 && abs(middle-2205)<=1)
precondition(impulse.left[first]>0.1 && impulse.left[last]>0.1 && impulse.right[middle] < -0.1)
// Independent channels: center event cannot leak into the boundary-only channel.
precondition(impulse.left[2000..<2400].allSatisfy{abs($0)<0.000001})
precondition(impulse.right[0..<128].allSatisfy{abs($0)<0.000001})
let impulseAfter=try Data(contentsOf:impulseURL);precondition(impulseBefore==impulseAfter)

let exactLimitURL=try fixture("exact-limit-resample",rate:48000,channels:2,frames:480000)
let exactLimit=try stage("resampled exact ten second boundary") {try SeparationAudioImport.decode(exactLimitURL)}
precondition(exactLimit.left.count==441000 && exactLimit.right.count==441000)
let long=try fixture("long",rate:44100,channels:2,frames:441001)
do {_=try SeparationAudioImport.decode(long);fatalError("overlong input accepted")}catch{}
// A three-channel AVAudioFormat needs an explicit channel layout. Build a
// standard WAVE_FORMAT_EXTENSIBLE PCM fixture with the front-left/right/center
// speaker mask instead of force-unwrapping the channel-count-only initializer.
let multichannel=root.appendingPathComponent("surround.wav")
try stage("create explicit-layout three-channel PCM WAV") {
    var data=Data()
    func word<T:FixedWidthInteger>(_ x:T) {var value=x.littleEndian;withUnsafeBytes(of:&value){data.append(contentsOf:$0)}}
    let byteCount=4410*3*2
    data.append(contentsOf:"RIFF".utf8);word(UInt32(60+byteCount));data.append(contentsOf:"WAVEfmt ".utf8)
    word(UInt32(40));word(UInt16(0xfffe));word(UInt16(3));word(UInt32(44100));word(UInt32(44100*6))
    word(UInt16(6));word(UInt16(16));word(UInt16(22));word(UInt16(16));word(UInt32(7))
    data.append(contentsOf:[UInt8](arrayLiteral:1,0,0,0,0,0,16,0,128,0,0,170,0,56,155,113))
    data.append(contentsOf:"data".utf8);word(UInt32(byteCount))
    for _ in 0..<4410 {word(Int16(4096));word(Int16(-8192));word(Int16(2048))}
    try data.write(to:multichannel,options:.withoutOverwriting)
}
try stage("verify valid three-channel source before policy rejection") {
    let file=try AVAudioFile(forReading:multichannel,commonFormat:.pcmFormatFloat32,interleaved:false)
    precondition(file.processingFormat.channelCount==3 && file.length==4410)
}
try stage("reject supported-decoder but unsupported-policy channel count") {
    do {_=try SeparationAudioImport.decode(multichannel);throw ProbeFailure(description:"multichannel accepted")}
    catch SeparationStore.Failure.invalid {} // Reject by our channel policy, not an unreadable fixture.
}
print("Stereo, mono, resampling, source preservation and full-length bounds passed")

}
do {try run()}
catch {
    FileHandle.standardError.write(Data(("FAIL separation import probe: "+String(reflecting:error)+"\n").utf8))
    exit(1)
}
