#if os(iOS)
import SwiftUI
import UIKit

struct ClipSpeakerReviewView: View {
    @EnvironmentObject private var local: LocalVideoStudio
    @EnvironmentObject private var audio: AudioStore
    @Environment(\.scenePhase) private var scene
    @StateObject private var review = ClipSpeakerReviewCoordinator()
    @State private var visible = false
    @StateObject private var consent = ClipSpeakerReviewConsent()
    @State private var drafts: [String: String] = [:]

    @State private var turnDrafts: [Int: String] = [:]

    let clip: SeparationClipHandoff.Input
    let source: SeparationClipHandoff.Source

    private var isCurrent: Bool {
        visible && scene == .active && UIApplication.shared.applicationState == .active && local.retainedSeparationSource == source
    }

    private var unavailable: Bool { !isCurrent || review.busy || audio.processingInUse || audio.microphoneInUse }

    var body: some View {
        Form {
            Section("Analysis only · on this iPhone") {
                Text("Find anonymous model guesses for who spoke when in this clip. No upload, voice creation or training.")
                Text(String(format: "Retained source %.2f–%.2f s. Turn times below are relative to the clip.",
                            clip.start, clip.start + Double(clip.frames) / 44_100)).font(.caption)
                Button(audio.playing == clip.url ? "Stop listening" : "Listen to retained clip") {
                    guard isCurrent else { return }
                    review.togglePlayback(clip, audio: audio)
                }
                .disabled(unavailable || !review.verified)
                .accessibilityIdentifier("clip-speaker-review-listen")
            }
            Section("Speaker turns") {
                if review.verified, review.result == nil, !review.busy {
                    authorizationToggle(epoch: consent.epoch)
                    Button("Find speaker turns") {
                        let permission = consent.authorized
                        consent.invalidate()
                        review.start(clip, authorized: permission, audio: audio, isCurrent: { isCurrent })
                    }
                    .disabled(!consent.authorized || unavailable)
                    .accessibilityIdentifier("clip-speaker-review-run")
                }
                if review.busy {
                    ProgressView()
                    Button("Cancel analysis", role: .cancel) { consent.invalidate(); review.cancel() }
                        .disabled(review.cancelling)
                        .accessibilityIdentifier("clip-speaker-review-cancel")
                }
                Text(review.status).accessibilityIdentifier("clip-speaker-review-status")
                if let result = review.result, result.hasOverlap {
                    Text("Possible overlapping speech detected. These turns are not isolated audio.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("clip-speaker-review-overlap")
                }
            }
            if let result = review.result {
                Text("Automatic grouping is uncertain and may group different speakers together. A manual turn label applies only to that interval.")
                    .font(.caption)
                    .accessibilityIdentifier("clip-speaker-review-grouping-uncertainty")
                ForEach(result.groups) { group in
                    Section {
                        if let alias = result.alias(for: group.speaker) {
                            Text("Your label: \(alias)").accessibilityIdentifier("clip-speaker-review-alias-" + group.id)
                        }
                        if !group.hasPolicyWindow {
                            Text("No clean window met the existing speaker policy. A guessed turn is not a usable voice reference here.")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("clip-speaker-review-no-window-" + group.id)
                        }
                        TextField("Optional label for \(group.id)", text: Binding(
                            get: { drafts[group.id] ?? result.alias(for: group.speaker) ?? "" },
                            set: { drafts[group.id] = $0 }
                        ))
                        .disabled(unavailable)
                        .accessibilityIdentifier("clip-speaker-review-label-" + group.id)
                        Button("Save label") {
                            guard isCurrent else { return }
                            if let draft = drafts[group.id] {
                                review.saveAlias(draft, speaker: group.speaker, for: clip)
                                if review.result?.alias(for: group.speaker) == (try? ClipSpeakerReviewStore.checkedAlias(draft)) {
                                    drafts[group.id] = nil
                                }
                            }
                        }
                        .disabled(unavailable || drafts[group.id] == nil)
                        .accessibilityIdentifier("clip-speaker-review-save-" + group.id)
                        if result.alias(for: group.speaker) != nil {
                            Button("Remove label") {
                                guard isCurrent else { return }
                                review.saveAlias(nil, speaker: group.speaker, for: clip)
                                drafts[group.id] = nil
                            }
                            .disabled(unavailable)
                            .accessibilityIdentifier("clip-speaker-review-remove-" + group.id)
                        }
                        ForEach(group.turns) { turn in
                            turnControls(turn, result: result)
                        }
                    } header: {
                        Text("Speaker guess \(group.id)")
                            .accessibilityIdentifier("clip-speaker-review-speaker-" + group.id)
                    }
                }
            }
        }
        .navigationTitle("Review speaker turns")
        .accessibilityIdentifier("clip-speaker-review")
        .onAppear { visible = true; synchronize() }
        .onDisappear { visible = false; synchronize() }
        .onChange(of: scene) { _,_ in synchronize() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            suspendReview()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            synchronize()
        }
        .onChange(of: clip) { previous,_ in
            if audio.playing == previous.url { audio.stop() }
            synchronize()
        }
        .onChange(of: local.retainedSeparationSource) { _,_ in synchronize() }
    }

    private func authorizationToggle(epoch: UUID) -> some View {
        Toggle("I am authorized to analyze this clip and its voices", isOn: Binding(
            get: { consent.authorized },
            set: { value in
                consent.set(value, epoch: epoch, isCurrent: isCurrent && review.verified && !review.busy)
            }
        ))
        .id(epoch)
        .disabled(unavailable)
        .accessibilityIdentifier("clip-speaker-review-authorization")
    }

    @ViewBuilder
    private func turnControls(_ turn: ClipSpeakerReviewStore.Turn, result: ClipSpeakerReviewStore.Review) -> some View {
        let key = String(turn.index)
        let interval = String(format: "%.2f–%.2f s", turn.start, min(turn.end, Double(clip.frames) / 44_100))
        Text(interval).monospacedDigit()
        if let name = result.turnLabel(for: turn) {
            Text("Your turn label: \(name)")
                .accessibilityIdentifier("clip-speaker-review-turn-name-" + key)
        }
        TextField("Label turn \(interval)", text: Binding(
            get: { turnDrafts[turn.id] ?? result.turnLabel(for: turn) ?? "" },
            set: { turnDrafts[turn.id] = $0 }
        ))
        .disabled(unavailable)
        .accessibilityIdentifier("clip-speaker-review-turn-label-" + key)
        Button("Save turn label for \(interval)") {
            guard isCurrent, let draft = turnDrafts[turn.id] else { return }
            review.saveTurnLabel(draft, turn: turn, for: clip)
            if review.result?.turnLabel(for: turn) == (try? ClipSpeakerReviewStore.checkedAlias(draft)) {
                turnDrafts[turn.id] = nil
            }
        }
        .disabled(unavailable || turnDrafts[turn.id] == nil)
        .accessibilityIdentifier("clip-speaker-review-turn-save-" + key)
        if result.turnLabel(for: turn) != nil {
            Button("Remove turn label for \(interval)") {
                guard isCurrent else { return }
                review.saveTurnLabel(nil, turn: turn, for: clip)
                turnDrafts[turn.id] = nil
            }
            .disabled(unavailable)
            .accessibilityIdentifier("clip-speaker-review-turn-remove-" + key)
        }
    }

    private func suspendReview() {
        consent.invalidate()
        drafts = [:]
        turnDrafts = [:]
        review.deactivate()
        if audio.playing == clip.url { audio.stop() }
    }

    private func synchronize() {
        consent.invalidate()
        drafts = [:]
        turnDrafts = [:]
        if isCurrent {
            review.activate(clip)
        } else {
            review.deactivate()
            if audio.playing == clip.url { audio.stop() }
        }
    }
}
#endif
