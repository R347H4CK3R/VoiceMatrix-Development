import Foundation
import AVFoundation

@main struct ReferenceAudioChecks {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let complete = root.appendingPathComponent("complete.wav")
        let short = root.appendingPathComponent("short-audio.mp4")
        let originals = try [Data(contentsOf: complete), Data(contentsOf: short)]
        for (start, seconds) in [(0.0, 0.5), (0.2, 1.0), (1.5, 0.5)] {
            let reference = try await LocalVideoAudio.extract(source: complete, start: start, seconds: seconds)
            guard abs(reference.seconds - seconds) <= 0.05,
                  reference.wave.count > 44, reference.rms > 0.001 else {
                fatalError("Complete reference lost duration or audible content")
            }
        }
        let duration = try await AVURLAsset(url: short).load(.duration).seconds
        guard duration >= 2.9 else { fatalError("Invalid regression fixture: expected three-second video") }
        do {
            _ = try await LocalVideoAudio.extract(source: short, start: 0, seconds: 2)
            fatalError("Incomplete audio track accepted as a two-second reference")
        } catch LocalVideoAudio.Failure.unusableAudio {
            // The actual decoder completed, but its PCM did not cover the interval.
        }
        guard try Data(contentsOf: complete) == originals[0],
              Data(contentsOf: short) == originals[1] else { fatalError("Source mutated") }
        print("PASS: real AVFoundation extraction at start/end/minimum boundaries; short audio rejected; sources unchanged. macOS host only, not iPhone verification.")
    }
}
