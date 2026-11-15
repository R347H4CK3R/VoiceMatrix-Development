import XCTest
@testable import FluidAudio

final class EOFTimelineTests: XCTestCase {
    private func build(duration: Double, active: Range<Int>, second: Range<Int> = 0..<0, offset: Double = 0) -> [TimedSpeakerSegment] {
        let config = OfflineDiarizerConfig(minSegmentDuration: 0.01, minGapDuration: 0,
            segmentationMinDurationOn: 0, segmentationMinDurationOff: 0)
        let weights: [[Float]] = (0..<100).map { [active.contains($0) ? 1 : 0, second.contains($0) ? 1 : 0] }
        let segmentation = SegmentationOutput(logProbs: [[[0]]], speakerWeights: [weights],
            numChunks: 1, numFrames: 100, numSpeakers: 2, chunkOffsets: [offset], frameDuration: 0.1)
        return OfflineReconstruction(config: config).buildSegments(segmentation: segmentation,
            hardClusters: [[0, 1]], centroids: [[1, 0], [0, 1]], audioDuration: duration)
    }
    func testExactEOF() {
        let segments = build(duration: 2, active: 0..<100)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(Double(segments[0].endTimeSeconds), 2, accuracy: 1e-6)
    }
    func testPartialFinalFrameOnlyIntersectsExistingAudio() {
        let segments = build(duration: 2.05, active: 0..<100)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(Double(segments[0].endTimeSeconds), 2.05, accuracy: 1e-6)
    }
    func testPaddingDoesNotBecomeSpeechAtEOF() {
        XCTAssertTrue(build(duration: 2, active: 20..<100).isEmpty)
        XCTAssertTrue(build(duration: 2.05, active: 21..<100).isEmpty)
    }
    func testUnalignedPaddingDoesNotVoteIntoLastFrame() {
        XCTAssertTrue(build(duration: 2.04, active: 20..<100, offset: 0.06).isEmpty)
        let segments = build(duration: 2.04, active: 19..<20, offset: 0.06)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(Double(segments[0].startTimeSeconds), 2, accuracy: 1e-6)
        XCTAssertEqual(Double(segments[0].endTimeSeconds), 2.04, accuracy: 1e-6)
    }
    func testRealOverlapRemainsOverlap() {
        let segments = build(duration: 2.05, active: 0..<100, second: 10..<100)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.map(\.speakerId), ["S1", "S2"])
        XCTAssertEqual(Double(segments[1].startTimeSeconds), 1, accuracy: 1e-6)
        for segment in segments { XCTAssertEqual(Double(segment.endTimeSeconds), 2.05, accuracy: 1e-6) }
    }
    func testInvalidAudioBoundsFailClosed() {
        for duration in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertTrue(build(duration: duration, active: 0..<100).isEmpty)
        }
    }
    func testZeroVoteEmbeddingDoesNotReadPadding() {
        var config = OfflineDiarizerConfig(minSegmentDuration: 0.01, minGapDuration: 0,
            segmentationMinDurationOn: 0, segmentationMinDurationOff: 0)
        config.zeroVoteReembed = .init(enabled: true, minDurationSeconds: 0.1)
        let segmentation = SegmentationOutput(logProbs: [[[0]]],
            speakerWeights: [Array(repeating: [Float(1)], count: 100)],
            numChunks: 1, numFrames: 100, numSpeakers: 1, chunkOffsets: [0], frameDuration: 0.1)
        var spans: [(Double, Double)] = []
        let segments = OfflineReconstruction(config: config).buildSegments(
            segmentation: segmentation, hardClusters: [[-2]], centroids: [[1, 0]], audioDuration: 2.05,
            spanEmbedder: { start, end in spans.append((start,end)); return [1,0] })
        XCTAssertFalse(spans.isEmpty)
        XCTAssertFalse(segments.isEmpty)
        for (start,end) in spans {
            XCTAssertLessThan(start,end)
            XCTAssertLessThanOrEqual(end,2.05)
        }
        XCTAssertEqual(spans.last!.1,2.05,accuracy: 1e-6)
    }
    func testRealSpeechEndingBeforeEOFNotExtended() {
        let segments = build(duration: 2.05, active: 0..<10)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(Double(segments[0].endTimeSeconds), 1, accuracy: 1e-6)
    }
}
