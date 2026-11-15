import Foundation
@main struct Checks {
    static func main() {
        precondition(LocalStudioEvidence.wordErrorRate(expected: "I found a strange device near the portal.", actual: "Found a strange device near the portal.") > 0.1)
        precondition(LocalStudioEvidence.wordErrorRate(expected: "HELLO world!", actual: "hello world") == 0)
        precondition(!LocalStudioEvidence.usableTranscript("♪ music is playing"))
        precondition(LocalStudioEvidence.windows(duration: .nan).isEmpty)
        for duration in [3.0, 7.5, 17, 1800] {
            let windows = LocalStudioEvidence.windows(duration: duration)
            precondition(!windows.isEmpty && windows.count <= 300)
            precondition(windows.allSatisfy { $0.start >= 0 && $0.seconds >= 3 && $0.seconds <= 8 && $0.start + $0.seconds <= duration })
        }
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 24000, requestedSeconds: 1))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 23760, requestedSeconds: 1))
        precondition(!LocalStudioEvidence.referenceCoversInterval(frames: 24000, requestedSeconds: 2))
        precondition(!LocalStudioEvidence.referenceCoversInterval(frames: 24000, requestedSeconds: 0.5))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 22800, requestedSeconds: 1))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 25200, requestedSeconds: 1))
        precondition(!LocalStudioEvidence.referenceCoversInterval(frames: 22799, requestedSeconds: 1))
        precondition(!LocalStudioEvidence.referenceCoversInterval(frames: 25201, requestedSeconds: 1))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 12000, requestedSeconds: 0.5))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 11991, requestedSeconds: 0.5))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 10800, requestedSeconds: 0.5))
        precondition(LocalStudioEvidence.referenceCoversInterval(frames: 360000, requestedSeconds: 15))
        for seconds in [Double.nan, Double.infinity, 0.49, 15.01] {
            precondition(!LocalStudioEvidence.referenceCoversInterval(frames: 24000, requestedSeconds: seconds))
        }
        for frames in [-1, 0, 10799, 360001] {
            precondition(!LocalStudioEvidence.referenceCoversInterval(frames: frames, requestedSeconds: 0.5))
        }
        precondition(LocalStudioEvidence.referenceTimestampMatches(timestamp: 2.5, start: 2, decodedFrames: 12000))
        precondition(LocalStudioEvidence.referenceTimestampMatches(timestamp: 2.52, start: 2, decodedFrames: 12000))
        for timestamp in [Double.nan, Double.infinity, 0, 2.7] {
            precondition(!LocalStudioEvidence.referenceTimestampMatches(timestamp: timestamp, start: 2, decodedFrames: 12000))
        }
        precondition(!LocalStudioEvidence.referenceTimestampMatches(timestamp: 0, start: -1, decodedFrames: 24000))
        precondition(!LocalStudioEvidence.referenceTimestampMatches(timestamp: 0, start: 0, decodedFrames: -1))
        print("Native local evidence checks passed; no model inference was performed")
    }
}
