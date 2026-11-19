import Foundation

/// Analysis-only route. It does not enter the video generation pipeline.
enum ClipSpeakerReviewAnalyzer {
    static func analyze(_ clip: SeparationClipHandoff.Input, store: ClipSpeakerReviewStore,
                        bundle: URL? = Bundle.main.url(forResource: "Diarization", withExtension: nil),
                        progress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> LocalSpeakerDiarization.Analysis {
        let snapshot = try store.snapshot(for: clip)
        defer { try? FileManager.default.removeItem(at: snapshot) } // Only this request's private scratch copy.
        let analysis = try await LocalSpeakerDiarization.analyze(source: snapshot, bundle: bundle, retainedClipFrames: clip.frames, progress: progress)
        try Task.checkCancellation()
        try store.verify(clip)
        try store.validate(analysis, for: clip)
        return analysis
    }
}

#if os(iOS)
import Combine
import FluidAudio

@MainActor final class ClipSpeakerReviewCoordinator: ObservableObject {
    typealias Clip = SeparationClipHandoff.Input
    typealias Review = ClipSpeakerReviewStore.Review
    typealias Analyze = @Sendable (Clip, ClipSpeakerReviewStore, @escaping @Sendable (String) -> Void) async throws -> LocalSpeakerDiarization.Analysis

    @Published private(set) var result: Review?
    @Published private(set) var verified = false
    @Published private(set) var busy = false
    @Published private(set) var cancelling = false
    @Published private(set) var status = "Check the retained clip to begin."

    private let store: ClipSpeakerReviewStore
    private let analyze: Analyze
    private var activeClip: Clip?
    private var request: UUID?
    private var work: Task<Void, Never>?

    init(store: ClipSpeakerReviewStore = ClipSpeakerReviewStore(), analyze: @escaping Analyze = { clip, store, progress in
        try await ClipSpeakerReviewAnalyzer.analyze(clip, store: store, progress: progress)
    }) {
        self.store = store
        self.analyze = analyze
    }

    /// Opening or returning to the screen only verifies existing files.
    func activate(_ clip: Clip) {
        guard activeClip != clip else { return }
        if activeClip != nil { deactivate() }
        activeClip = clip
        do {
            result = try store.load(for: clip)
            verified = true
            status = result.map(description) ?? "Verified clip. Authorize this clip and tap Find speaker turns to analyze it on this iPhone."
        } catch {
            result = nil
            verified = false
            status = error is ClipSpeakerReviewStore.Failure ? error.localizedDescription : ClipSpeakerReviewStore.Failure.unsafe.localizedDescription
        }
    }

    func deactivate() {
        cancel()
        activeClip = nil
        verified = false
        result = nil
        status = "Speaker review is not active."
    }

    func cancel() {
        // Invalidate before cooperative cancellation; Core ML can finish its current call.
        request = nil
        guard busy else { return }
        cancelling = true
        status = "Stopping safely. Audio stays reserved until the model finishes its current work."
        work?.cancel()
    }

    @discardableResult
    func start(_ clip: Clip, authorized: Bool, audio: AudioStore,
               isCurrent: @escaping @MainActor () -> Bool) -> Bool {
        guard authorized, activeClip == clip, verified, result == nil, !busy,
              isCurrent(), let lease = audio.claimProcessing() else { return false }

        busy = true
        cancelling = false
        audio.stop()
        status = "Checking the clip and starting local speaker analysis…"
        let token = UUID()
        request = token
        work = Task {
            defer {
                audio.releaseProcessing(lease)
                busy = false
                if cancelling, activeClip == clip {
                    status = "Stopped. No new review was saved."
                }
                cancelling = false
                request = nil
                work = nil
            }
            do {
                let worker = Task.detached(priority: .userInitiated) { [store, analyze, weak self] in
                    try Task.checkCancellation()
                    try store.verify(clip)
                    return try await analyze(clip, store) { [weak self] update in
                        Task { @MainActor in
                            guard let self, self.request == token, self.activeClip == clip else { return }
                            self.status = update
                        }
                    }
                }
                let analysis = try await withTaskCancellationHandler(operation: { try await worker.value },
                                                                     onCancel: { worker.cancel() })
                try Task.checkCancellation()
                guard request == token, activeClip == clip, isCurrent() else { return }
                // Last verification and atomic publication do not suspend. A deactivation or
                // cancellation observed on this actor cannot be crossed by a late result.
                let saved = try store.publish(analysis, for: clip)
                result = saved
                status = description(saved)
            } catch is CancellationError {
                if request == token, activeClip == clip, isCurrent() { status = "Stopped. No new review was saved." }
            } catch {
                guard request == token, activeClip == clip, isCurrent() else { return }
                status = friendly(error)
            }
        }
        return true
    }

    func saveAlias(_ name: String?, speaker: String, for clip: Clip) {
        guard !busy, verified, activeClip == clip, let result else { return }
        do {
            self.result = try store.saveAlias(name, speaker: speaker, expected: result, for: clip)
            status = name == nil ? "Label removed." : "Label saved only for this clip and speaker guess."
        } catch {
            if (error as? ClipSpeakerReviewStore.Failure) != .alias {
                verified = false
                self.result = nil
            }
            status = friendly(error)
        }
    }

    func saveTurnLabel(_ name: String?, turn: ClipSpeakerReviewStore.Turn, for clip: Clip) {
        guard !busy, verified, activeClip == clip, let result else { return }
        do {
            self.result = try store.saveTurnLabel(name, turn: turn, expected: result, for: clip)
            status = name == nil ? "Turn label removed." : "Label saved only for this turn."
        } catch {
            if (error as? ClipSpeakerReviewStore.Failure) != .alias,
               (error as? ClipSpeakerReviewStore.Failure) != .bounds {
                verified = false
                self.result = nil
            }
            status = friendly(error)
        }
    }

    func togglePlayback(_ clip: Clip, audio: AudioStore) {
        guard !busy, verified, activeClip == clip, !audio.processingInUse, !audio.microphoneInUse else { return }
        if audio.playing == clip.url { audio.stop(); return }
        do {
            try store.verify(clip)
            audio.play(clip.url)
            if let error = audio.error { status = error }
        } catch {
            verified = false
            result = nil
            status = friendly(error)
        }
    }

    private func description(_ review: Review) -> String {
        review.groups.isEmpty
            ? "No usable speaker turns were found. Speech or overlap may still be present."
            : "Local speaker guesses are ready to review. They do not identify people or verify clean references."
    }

    private func friendly(_ error: Error) -> String {
        if let diarization = error as? OfflineDiarizationError, case .noSpeechDetected = diarization {
            return "No usable speaker turns were found. Speech or overlap may still be present."
        }
        if error is ClipSpeakerReviewStore.Failure || error is LocalSpeakerDiarization.Failure { return error.localizedDescription }
        return "The clip or its speaker evidence could not be verified. Existing files were kept."
    }
}
#endif
