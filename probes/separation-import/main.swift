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
let multichannel=try fixture("surround",rate:44100,channels:3,frames:4410)
do {_=try SeparationAudioImport.decode(multichannel);fatalError("multichannel accepted")}catch{}
print("Stereo, mono, resampling, source preservation and full-length bounds passed")

}
do {try run()}
catch {
    FileHandle.standardError.write(Data(("FAIL separation import probe: "+String(reflecting:error)+"\n").utf8))
    exit(1)
}
