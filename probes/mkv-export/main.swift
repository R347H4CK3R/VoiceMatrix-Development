import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
    static func run() async throws {
        let args = CommandLine.arguments
        if args.count == 2 && args[1] == "--aac-policy" { try aacPolicy(); return }
        guard args.count == 3 || args.count == 4 else { fatalError("input.mp4 output.mkv") }
        let input = URL(fileURLWithPath: args[1])
        if args.count == 4 && args[3] == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
        _ = try await LocalMKVExport.export(input: input, destination: URL(fileURLWithPath: args[2]), maxBytes: args.count == 4 ? (Int64(args[3]) ?? 536_870_912) : 536_870_912) { _ in }
    }
    static func main() async {
        do { try await run() }
        catch { FileHandle.standardError.write(Data("EXPORT_REJECTED \(error)\n".utf8)); exit(1) }
    }
}
