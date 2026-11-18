import Foundation

@main struct Probe {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3 || args.count == 4 else { fatalError("input.mp4 output.mkv") }
        if args.count == 4 && args[3] == "cancel" { withUnsafeCurrentTask { $0?.cancel() } }
        _ = try await LocalMKVExport.export(input: URL(fileURLWithPath: args[1]), destination: URL(fileURLWithPath: args[2]), maxBytes: args.count == 4 ? (Int64(args[3]) ?? 536_870_912) : 536_870_912) { _ in }
    }
}
