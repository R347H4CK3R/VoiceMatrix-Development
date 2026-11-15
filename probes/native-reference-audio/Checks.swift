import Foundation
import AVFoundation

@main struct ReferenceAudioChecks {
    static func log(_ message: String) { FileHandle.standardError.write(Data((message+"\n").utf8)) }
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let complete = root.appendingPathComponent("complete.wav")
        let short = root.appendingPathComponent("short-audio.mp4")
        let offset = root.appendingPathComponent("offset-audio.mov")
        let originals = try [Data(contentsOf: complete), Data(contentsOf: short), Data(contentsOf: offset)]
        for (start, seconds) in [(0.0, 0.5), (0.0, 0.501), (0.2, 1.0), (1.5, 0.5)] {
            log("CASE complete start=\(start) seconds=\(seconds)")
            let reference = try await LocalVideoAudio.extract(source: complete, start: start, seconds: seconds, diagnostic: log)
            guard abs(reference.seconds - seconds) <= 0.05,
                  reference.wave.count > 44, reference.rms > 0.001,
                  reference.seconds == Double((reference.wave.count - 44) / 2) / 24000 else {
                fatalError("Complete reference lost duration or audible content")
            }
        }
        let duration = try await AVURLAsset(url: short).load(.duration).seconds
        guard duration >= 2.9 else { fatalError("Invalid regression fixture: expected three-second video") }
        do {
            _ = try await LocalVideoAudio.extract(source: short, start: 0, seconds: 2, diagnostic: log)
            fatalError("Incomplete audio track accepted as a two-second reference")
        } catch LocalVideoAudio.Failure.unusableAudio {
            // The actual decoder completed, but its PCM did not cover the interval.
        }
        let offsetTracks = try await AVURLAsset(url: offset).loadTracks(withMediaType: .audio)
        guard offsetTracks.count == 1 else { fatalError("Invalid offset fixture track count") }
        let segments = try await offsetTracks[0].load(.segments)
        let mediaStarts = segments.filter { !$0.isEmpty }.map { $0.timeMapping.target.start.seconds }
        log("Offset media segment starts: \(mediaStarts)")
        guard let firstMedia = mediaStarts.min(), abs(firstMedia - 0.2) < 0.01 else { fatalError("Offset fixture lost its 200 ms delay") }
        do {
            _ = try await LocalVideoAudio.extract(source: offset, start: 0, seconds: 1, diagnostic: log)
            fatalError("Offset speech admitted at the wrong source timestamp")
        } catch LocalVideoAudio.Failure.invalidTimeline {
            // A generic duration rejection is insufficient for this regression.
        }
        let aligned = try await LocalVideoAudio.extract(source: offset, start: 0.2, seconds: 1, diagnostic: log)
        guard abs(aligned.seconds - 1) <= 0.05 else { fatalError("Correctly aligned offset audio rejected") }
        guard try Data(contentsOf: complete) == originals[0],
              try Data(contentsOf: short) == originals[1], try Data(contentsOf: offset) == originals[2] else { fatalError("Source mutated") }
        print("PASS: real AVFoundation extraction at start/end/minimum boundaries; short audio and misaligned timestamps rejected; aligned offset accepted; sources unchanged. macOS host only, not iPhone verification.")
    }
}
