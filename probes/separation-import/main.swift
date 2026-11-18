import Foundation
import AVFoundation
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
func fixture(_ name:String,rate:Double,channels:AVAudioChannelCount,frames:AVAudioFrameCount) throws -> URL {
    let url=root.appendingPathComponent(name+".wav")
    let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:channels,interleaved:false)!
    let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:frames)!
    buffer.frameLength=frames
    for c in 0..<Int(channels) {for i in 0..<Int(frames) {buffer.floatChannelData![c][i]=c==0 ? 0.125 : -0.25}}
    var file:AVAudioFile?=try AVAudioFile(forWriting:url,settings:format.settings)
    try file!.write(from:buffer);file=nil
    return url
}
let stereo=try fixture("stereo",rate:44100,channels:2,frames:4410)
let before=try Data(contentsOf:stereo)
let a=try SeparationAudioImport.decode(stereo)
precondition(a.left.count==4410 && a.right.count==4410)
precondition(a.left.allSatisfy{$0==0.125} && a.right.allSatisfy{$0 == -0.25})
let after=try Data(contentsOf:stereo);precondition(before==after)
let mono=try fixture("mono",rate:44100,channels:1,frames:4410)
let b=try SeparationAudioImport.decode(mono)
precondition(b.left==b.right && b.left.count==4410)
let resampled=try fixture("resample",rate:48000,channels:2,frames:4800)
let c=try SeparationAudioImport.decode(resampled)
precondition(c.left.count==4410 && c.right.count==4410)
let long=try fixture("long",rate:44100,channels:2,frames:441001)
do {_=try SeparationAudioImport.decode(long);fatalError("overlong input accepted")}catch{}
let multichannel=try fixture("surround",rate:44100,channels:3,frames:4410)
do {_=try SeparationAudioImport.decode(multichannel);fatalError("multichannel accepted")}catch{}
print("Stereo, mono, resampling, source preservation and full-length bounds passed")
