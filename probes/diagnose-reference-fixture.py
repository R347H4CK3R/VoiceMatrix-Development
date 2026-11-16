#!/usr/bin/env python3
"""Stage exact source functions plus lifecycle-only fixture variants; no product edits."""
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.')
out=pathlib.Path(sys.argv[2] if len(sys.argv)>2 else 'fixture-diagnostic');out.mkdir(parents=True,exist_ok=True)
source=(root/'VoiceMatrix/OnDeviceTranscription.swift').read_text()
start=source.index('    nonisolated static func referenceLeadingBuffer(')
end=source.index('    private nonisolated static func recoveryBuffer(',start)
method=source[start:end]
policy=(root/'VoiceMatrix/BundledASRPolicy.swift').read_text()
test=(root/'VoiceMatrixTests/ReferenceLeadingContextTests.swift').read_text()
start=test.index('    private func fixture(');end=test.index('    func testReferenceContextRetains',start)
fixture=test[start:end].replace('private func fixture(', 'func oldFixture(',1)
assert 'let file = try AVAudioFile(forWriting: url, settings: format.settings)' in fixture
explicit=fixture.replace('func oldFixture(', 'func releasedFixture(',1).replace('let file = try AVAudioFile(forWriting: url, settings: format.settings)\n        try file.write(from: buffer)', 'var file: AVAudioFile? = try AVAudioFile(forWriting: url, settings: format.settings)\n        try file!.write(from: buffer)\n        file = nil')
(out/'BundledASRPolicy.swift').write_text(policy)
(out/'main.swift').write_text('''import Foundation
import AVFoundation

enum OnDeviceTranscription {
    enum Failure: Error { case invalidAudio }
'''+method+'}\n'+fixture+explicit+'''
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
var results = [[String: Any]]()
for variant in ["original", "explicitRelease", "autoreleasepool"] {
    for iteration in 0..<3 {
        var item: [String: Any] = ["variant":variant,"iteration":iteration]
        do {
            let file: URL
            if variant == "original" { file = try oldFixture(root) }
            else if variant == "explicitRelease" { file = try releasedFixture(root) }
            else { file = try autoreleasepool { try oldFixture(root) } }
            let before = try Data(contentsOf:file)
            item["bytesBefore"] = before.count
            // Execute exact production method before additional probes touch file metadata.
            do {
                let padded = try OnDeviceTranscription.referenceLeadingBuffer(file)
                let p = padded.floatChannelData![0]
                let valid = padded.frameLength == 30000 && (0..<6000).allSatisfy { p[$0] == 0 }
                    && (0..<24000).allSatisfy { p[$0+6000] == Float($0 % 101)/1000 }
                item["paddingAndEverySampleExact"] = valid
                item["productSuccess"] = true
            } catch { item["productSuccess"] = false; item["productError"] = String(describing:error) }
            item["sourceUnchanged"] = try Data(contentsOf:file) == before
            let values = try file.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            item["fileURL"] = file.isFileURL
            item["regular"] = values.isRegularFile ?? false
            item["symlink"] = values.isSymbolicLink ?? false
            item["metadataBytes"] = values.fileSize ?? -1
            let fresh = try URL(fileURLWithPath:file.path).resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            item["freshRegular"] = fresh.isRegularFile ?? false
            item["freshSymlink"] = fresh.isSymbolicLink ?? false
            item["freshBytes"] = fresh.fileSize ?? -1
            let audio = try AVAudioFile(forReading:file)
            item["frames"] = audio.length
            item["rate"] = audio.processingFormat.sampleRate
            item["channels"] = audio.processingFormat.channelCount
            item["format"] = String(describing:audio.processingFormat)
            item["leadFrames"] = BundledASRPolicy.referenceLeadingFrameCount(frames:Int(audio.length),sampleRate:audio.processingFormat.sampleRate) ?? -1
            if audio.length>0 && audio.length<=1440000,let buffer=AVAudioPCMBuffer(pcmFormat:audio.processingFormat,frameCapacity:AVAudioFrameCount(audio.length)) {
                try audio.read(into:buffer)
                item["readFrames"] = buffer.frameLength
                item["floatChannelPresent"] = buffer.floatChannelData != nil
            }
        } catch { item["diagnosticError"] = String(describing:error) }
        results.append(item)
        let data = try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:root.appendingPathComponent("results.json"),options:.atomic)
        print(String(data:try JSONSerialization.data(withJSONObject:item,options:.sortedKeys),encoding:.utf8)!)
    }
}
''')
(out/'source-pins.json').write_text(json.dumps({p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in ['VoiceMatrix/OnDeviceTranscription.swift','VoiceMatrix/BundledASRPolicy.swift','VoiceMatrixTests/ReferenceLeadingContextTests.swift']},indent=2)+'\n')
