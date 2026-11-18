import Foundation
import AVFoundation
import AudioToolbox

@main struct Probe {
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
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 2 && args[1] == "--aac-policy" { try aacPolicy(); return }
        guard args.count == 3 || args.count == 4 else { fatalError("input.mp4 output.mkv") }
        let input = URL(fileURLWithPath: args[1])
        try await evidence(input)
        if args.count == 4 && args[3] == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
        _ = try await LocalMKVExport.export(input: input, destination: URL(fileURLWithPath: args[2]), maxBytes: args.count == 4 ? (Int64(args[3]) ?? 536_870_912) : 536_870_912) { _ in }
    }
}
