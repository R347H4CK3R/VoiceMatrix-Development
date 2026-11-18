import UIKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalVideoStudioView: View {
    @Environment(\.scenePhase) private var clipScene
    @EnvironmentObject private var local: LocalVideoStudio
    @EnvironmentObject private var library: CharacterLibrary
    @EnvironmentObject private var audio: AudioStore
    @EnvironmentObject private var speech: SpeechStudio
    @State private var journalPage: LocalStudioJournal.Page?
    @State private var journalError: String?
    @State private var sourceURL = ""
    @State private var mkvExport: URL?
    @State private var importing = false
    @State private var selected: URL?
    @State private var authorized = false
    private struct FreshDownloadRequest: Identifiable { let id: UUID }
    @State private var retryRequest: FreshDownloadRequest?
    @State private var speakerDestination: CharacterStudioMode?
    @State private var selectionError: String?
    @State private var clipStart = "0"
    @State private var clipSeconds = "5"
    @State private var clipAuthorized = false
    @State private var clipPreparing = false
    @State private var clipMessage = ""
    @State private var clipWork: Task<Void,Never>?
    @State private var clipRequest: UUID?
    @State private var clipDestination: SeparationClipHandoff.Input?
    private let initialSeparatedVocals: SeparationStore.Result?
    @State private var separatedInput: SeparationStore.ReferenceInput?
    @State private var checkingSeparatedInput = false
    @State private var preparedSeparatedInput = false
    init(initialSourceURL: String? = nil, initialSeparatedVocals: SeparationStore.Result? = nil) {
        self.initialSeparatedVocals = initialSeparatedVocals
        let admitted = initialSourceURL.flatMap { try? LocalMediaURLPolicy.input($0).absoluteString }
        _sourceURL = State(initialValue: admitted ?? "")
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("On this iPhone").font(.title2.bold())
                Text("Import a local video or recording, or acquire supported public website media directly. Extraction, English transcription, reference-conditioned preview and voice registration run inside this app. No laptop or server fallback.")
                Text("Bundled analysis groups speakers and excludes detected overlap. Local sound screening rejects likely music, singing or insufficient speech. It does not identify characters, remove music or train RVC models. Every accepted reference must pass a word check; resemblance needs listening review.").font(.footnote).foregroundStyle(.secondary)
                Button(selected == nil ? "Choose video or audio" : "Choose a different file") { importing = true }
                    .buttonStyle(.bordered).disabled(local.busy || checkingSeparatedInput || clipPreparing).accessibilityIdentifier("local-video-import")
                if selected != nil { Label("Local media selected", systemImage: "doc.fill") }
                if separatedInput != nil {
                    Text("Separated vocals selected. Separation is not identity verification, voice cloning or training. Artifacts or remaining music can still fail the existing speech and reference checks.")
                        .font(.footnote).accessibilityIdentifier("local-video-separated-source")
                }
                if checkingSeparatedInput { ProgressView("Verifying saved vocals…") }
                TextField("YouTube or supported HTTPS media URL", text: $sourceURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .textFieldStyle(.roundedBorder).disabled(local.busy || checkingSeparatedInput || clipPreparing).accessibilityIdentifier("local-video-url")
                PasteButton(payloadType: String.self) { values in
                    authorized = false
                    if separatedInput != nil { selected = nil }
                    separatedInput = nil
                    guard values.count == 1, let raw = values.first, raw.utf8.count <= 16_384 else {
                        selectionError = "Clipboard must contain one supported video URL of at most 16,384 bytes."
                        return
                    }
                    do {
                        sourceURL = try LocalMediaURLPolicy.input(raw).absoluteString
                        selected = nil
                        selectionError = nil
                    } catch { selectionError = error.localizedDescription }
                }.buttonStyle(.bordered).disabled(local.busy || checkingSeparatedInput || clipPreparing)
                    .accessibilityLabel("Paste video URL from Clipboard")
                    .accessibilityIdentifier("local-video-paste")
                Text("URL acquisition needs internet to contact the source website. YouTube link support is limited: many public pages provide no downloadable media URLs. Direct media on upload.wikimedia.org or archive.org are supported candidates. A bundled resolver can try standard public streams on this iPhone. Sign-in, age/access verification and DRM are not bypassed; those sources need authorized local-file import.").font(.footnote).foregroundStyle(.secondary)
                Toggle("I am authorized to use this media and its voices", isOn: $authorized).disabled(local.busy || checkingSeparatedInput || clipPreparing).accessibilityIdentifier("local-video-authorization")
                Button("Generate speaker references") {
                    if let selected { local.start(selected, authorized: authorized, library: library, audio: audio, speech: speech, referenceInput: separatedInput) }
                }.buttonStyle(.borderedProminent).disabled(selected == nil || !authorized || local.busy || checkingSeparatedInput || clipPreparing)
                    .accessibilityIdentifier("local-video-generate")
                Button("Download URL and generate references") {
                    local.startURL(sourceURL, authorized: authorized, library: library, audio: audio, speech: speech)
                }.buttonStyle(.borderedProminent).disabled(sourceURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !authorized || local.busy || clipPreparing)
                    .accessibilityIdentifier("local-video-download")
                if let selectionError { Text(selectionError).foregroundStyle(.red) }
                Text(local.notice).accessibilityIdentifier("local-video-status")
                Text("Compatible H.264/AAC downloads also retain a genuine MKV export. Unsupported codecs, reordered frames or tight storage keep the verified MP4 fallback. Analysis uses the MP4 companion inside this app, not a laptop.").font(.footnote).foregroundStyle(.secondary)
                if let mkvExport, !local.busy {
                    ShareLink(item: mkvExport) { Label("Save or share retained MKV", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("local-video-share-mkv")
                }
                if local.busy {
                    ProgressView("Working on this iPhone…")
                    Button("Pause and retain files") { local.cancel() }.buttonStyle(.bordered)
                } else if let job = local.current, !job.completed, job.sourceFile != nil || job.acquisitionURL != nil {
                    if job.acquisitionURL != nil && job.sourceFile == nil {
                        if local.freshAcquisitionURL != nil {
                            Button("Try a fresh download") { retryRequest = FreshDownloadRequest(id: job.id) }
                                .buttonStyle(.bordered).accessibilityIdentifier("local-video-fresh-download")
                            Text("Resume reuses the retained download plan. A fresh attempt asks the original website again, which can help if its media links expired. It may still fail for unsupported or restricted sources.").font(.footnote).foregroundStyle(.secondary)
                        }
                        Button("Import an authorized local file instead") { importing = true }
                            .buttonStyle(.borderedProminent).disabled(checkingSeparatedInput || clipPreparing).accessibilityIdentifier("local-video-import-fallback")
                        Text("Choose a video or audio file you already have permission to use in Files, then enable authorization and tap Generate speaker references. The earlier job and its partial files remain retained.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Resume retained job") { local.resume(library: library, audio: audio, speech: speech) }.buttonStyle(.bordered).disabled(clipPreparing)
                }
                if local.retainedSeparationSource != nil {
                    GroupBox("Separate a short clip from retained media") {
                        VStack(alignment:.leading,spacing:10) {
                            Text("Choose 0.5–10 seconds from the retained source. This prepares only the selected clip, not the entire video. Experimental separation still needs a separate tap; it does not verify voice identity.").font(.footnote)
                            TextField("Start in seconds",text:$clipStart).keyboardType(.decimalPad)
                                .disabled(clipPreparing).accessibilityIdentifier("retained-clip-start")
                            TextField("Duration in seconds (0.5–10)",text:$clipSeconds).keyboardType(.decimalPad)
                                .disabled(clipPreparing).accessibilityIdentifier("retained-clip-seconds")
                            Toggle("I am authorized to use this selected clip and its voices",isOn:$clipAuthorized)
                                .disabled(clipPreparing).accessibilityIdentifier("retained-clip-authorization")
                            Button("Prepare selected clip for separation") {prepareSeparationClip()}
                                .disabled(!clipAuthorized || !clipIntervalValid || clipPreparing || audio.processingInUse || audio.microphoneInUse)
                                .accessibilityIdentifier("retained-clip-prepare")
                            if clipPreparing {
                                ProgressView("Verifying retained source and extracting selected clip…")
                                Button("Cancel clip preparation") {clipRequest=nil;clipWork?.cancel()}
                                    .accessibilityIdentifier("retained-clip-cancel")
                            }
                            Text(clipMessage).accessibilityIdentifier("retained-clip-status")
                        }
                    }
                }
                if let reference = local.reference { Button("Listen to reference") { audio.play(reference) }.disabled(local.busy) }
                if let preview = local.preview { Button("Listen to generated preview") { audio.play(preview) }.disabled(local.busy) }
                if let similarity=local.validatedSimilarity() {
                    VStack(alignment:.leading,spacing:4) {
                        Text("Recorded speaker similarity").font(.headline)
                        Text(String(format:"Cosine diagnostic: %.3f",similarity.report.cosineSimilarity)).font(.caption.monospaced())
                        Text("Measured " + similarity.measured.formatted(date:.abbreviated,time:.standard)).font(.caption)
                        Text("This is not a likeness percentage or identity verification. There is no calibrated acceptance threshold. Listen to both clips; the diagnostic describes only this retained reference/preview pair.").font(.caption).foregroundStyle(.secondary)
                    }.accessibilityIdentifier("local-video-similarity")
                }
                if local.current?.voiceID != nil {
                    NavigationLink("Browse saved voices") { CharacterLibraryView() }
                }
                if let job = local.current, let outcomes = job.speakerOutcomes, !outcomes.isEmpty {
                    Text("Speaker results").font(.headline)
                    ForEach(outcomes.keys.sorted(), id: \.self) { speaker in
                        DisclosureGroup("Unidentified speaker " + speaker) {
                            Text(outcomes[speaker] ?? "Pending").font(.caption)
                            if local.current?.speakerAssets?[speaker] != nil {
                                Text("Preview-only reference; not a trained RVC model. Identity and likeness are unverified.").font(.caption).foregroundStyle(.secondary)
                                Button("Make speech with this speaker") {
                                    openSpeaker(speaker, jobID: job.id, mode: .speech)
                                }.disabled(local.busy || library.busy || audio.processingInUse || audio.microphoneInUse)
                                    .accessibilityIdentifier("local-video-speaker-speech-" + speaker)
                                Button("Change my voice with this speaker") {
                                    openSpeaker(speaker, jobID: job.id, mode: .conversion)
                                }.disabled(local.busy || library.busy || audio.processingInUse || audio.microphoneInUse)
                                    .accessibilityIdentifier("local-video-speaker-conversion-" + speaker)
                                Button("Listen to this speaker's reference") {
                                    audio.stop()
                                    if let url=local.speakerAssetURL(speaker, preview: false) { audio.play(url) }
                                }.disabled(local.busy)
                                Button("Listen to this speaker's generated preview") {
                                    audio.stop()
                                    if let url=local.speakerAssetURL(speaker, preview: true) { audio.play(url) }
                                }.disabled(local.busy)
                            } else {
                                Text("No accepted per-speaker preview receipt is available for this job. Existing library voices and retained attempts are unchanged.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let evidence = local.current?.visualEvidence {
                    DisclosureGroup("Sampled visual evidence") {
                        Text("Visible text is not a verified character name. These frames coincide with a tentative speaker turn, but the actual speaker may be off screen. OCR confidence measures text recognition, not identity.").font(.caption)
                        if evidence.audioOnly { Text("Audio-only source; no frames available.").font(.caption) }
                        ForEach(evidence.frames) { frame in
                            VStack(alignment:.leading,spacing:6) {
                                Text("Unidentified speaker \(frame.speaker) · frame at \(frame.actualSeconds, specifier: "%.2f") s").font(.caption.bold())
                                if let data=local.visualFrameData(frame), let image=UIImage(data:data) {
                                    Image(uiImage:image).resizable().scaledToFit().frame(maxHeight:240)
                                        .accessibilityLabel("Sampled video frame; speaker identity unverified")
                                    ForEach(Array(frame.lines.enumerated()),id:\.offset) { _, line in
                                        Text("Visible text: \(line.text) · OCR \(Int(line.confidence * 100))%").font(.caption).textSelection(.enabled)
                                    }
                                    if frame.lines.isEmpty { Text("No readable English text detected in this frame.").font(.caption) }
                                } else { Text("Retained frame missing or changed; frame and OCR evidence not displayed.").font(.caption) }
                            }
                        }
                        if evidence.omittedSpeakers > 0 { Text("\(evidence.omittedSpeakers) speaker groups were not sampled to limit resource use.").font(.caption) }
                        if evidence.unavailableFrames > 0 { Text("\(evidence.unavailableFrames) requested frames were unavailable.").font(.caption) }
                    }.accessibilityIdentifier("local-video-visual-evidence")
                }
                Divider()
                Text("Live processing log").font(.headline)
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Log view refreshed " + timeline.date.formatted(date: .omitted, time: .standard)).font(.caption)
                        if let job = local.current {
                            Text((local.busy ? "Stage: " : "Not running · last retained stage: ") + job.stage).font(.headline)
                            Text("Last actual update: " + job.updated.formatted(date: .omitted, time: .standard)).font(.caption)
                            if local.busy, timeline.date.timeIntervalSince(job.updated) >= 30 {
                                Text("No new stage activity for \(Int(timeline.date.timeIntervalSince(job.updated))) seconds. The current operation may still be busy; this is not a failure declaration.").foregroundStyle(.orange)
                            }
                            ForEach(Array(job.events.reversed())) { event in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.time.formatted(date: .omitted, time: .standard) + " · " + event.stage).font(.caption.bold())
                                    Text(event.message).font(.caption)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else { Text("No local job has started.").font(.caption) }
                    }
                }.accessibilityIdentifier("local-video-live-log")
                if local.current != nil {
                    DisclosureGroup("Complete retained event history") {
                        Text("Oldest entries first, 100 per page. Older jobs may only have their previously saved snapshot. Refresh reads actual events without changing activity timestamps.").font(.caption)
                        Button("Refresh from first event") { loadJournal(0) }
                        if let journalError { Text(journalError).foregroundStyle(.orange) }
                        if let page=journalPage {
                            Text("Showing \(page.offset + (page.events.isEmpty ? 0 : 1))–\(page.offset + page.events.count) of \(page.total) retained events").font(.caption)
                            ForEach(page.events) { event in
                                Text(event.time.formatted(date:.abbreviated,time:.standard) + " · " + event.stage + "\n" + event.message).font(.caption).textSelection(.enabled)
                            }
                            HStack {
                                if page.offset>0 { Button("Previous 100") { loadJournal(max(0,page.offset-100)) } }
                                if let next=page.next { Button("Next 100") { loadJournal(next) } }
                            }
                            ShareLink("Share this log page",item:page.text)
                        }
                    }.accessibilityIdentifier("local-video-durable-log")
                }
                Text("Keep VoiceMatrix open while processing. Leaving the app pauses at a safe boundary. Files remain available for Resume; iOS does not guarantee unlimited background processing.").font(.footnote).foregroundStyle(.secondary)
                if local.historyReadFailures > 0 {
                    Text("\(local.historyReadFailures) retained job snapshots could not be reopened. Their source files, outputs and event journals were kept; no jobs were deleted.")
                        .font(.caption).foregroundStyle(.orange)
                        .accessibilityIdentifier("local-video-history-warning")
                }
                if !local.history.isEmpty {
                    Divider(); Text("Retained job history").font(.headline)
                    ForEach(local.history) { job in
                        Button { local.selectHistory(job) } label: {
                            VStack(alignment: .leading) {
                                Text(job.created.formatted(date: .abbreviated, time: .shortened))
                                Text(job.stage).font(.caption)
                            }
                        }.disabled(local.busy).accessibilityIdentifier("local-video-history-"+job.id.uuidString)
                    }
                }
            }.padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement:.keyboard) {
                Spacer()
                Button("Done") {UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}
                    .accessibilityIdentifier("local-video-keyboard-done")
            }
        }
        .navigationTitle("Video Voice Studio")
        .navigationDestination(item: $clipDestination) { input in
            VocalSeparationView(initialClip: input)
        }
        .onDisappear {clipRequest=nil;clipWork?.cancel();clipAuthorized=false}
        .onChange(of: clipScene) { _, value in
            if value != .active {clipRequest=nil;clipWork?.cancel();clipAuthorized=false}
        }
        .onChange(of: clipStart) {_,_ in clipAuthorized=false}
        .onChange(of: clipSeconds) {_,_ in clipAuthorized=false}
        .onChange(of: local.current?.id) {_,_ in clipRequest=nil;clipWork?.cancel();clipAuthorized=false}
        .navigationDestination(item: $speakerDestination) { mode in
            CharacterLibraryView(mode: mode)
        }
        .alert(item: $retryRequest) { request in
            Alert(title: Text("Start a fresh download?"),
                  message: Text("Confirm you are authorized to use this source and its voices. This contacts the original website again and starts a separate job. Previous jobs and files are kept; tracks from different attempts are never combined. Unsupported or restricted sources may still fail."),
                  primaryButton: .default(Text("Download original source again")) {
                      local.retryAcquisition(jobID: request.id, authorized: true, library: library, audio: audio, speech: speech)
                  }, secondaryButton: .cancel())
        }
        .task(id: "\(local.current?.id.uuidString ?? "none")-\(local.busy)") {
            mkvExport = nil
            mkvExport = await local.verifiedMKVExport()
        }
        .task {
            guard !preparedSeparatedInput, let result = initialSeparatedVocals else { return }
            preparedSeparatedInput = true
            authorized = false
            guard !local.busy, let lease = audio.claimProcessing() else {
                selectionError = "Stop the other audio job and reopen the saved vocals."
                return
            }
            checkingSeparatedInput = true
            defer { checkingSeparatedInput = false; audio.releaseProcessing(lease) }
            do {
                let worker = Task.detached { try SeparationStore.standard.referenceInput(for: result) }
                let input = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                separatedInput = input; selected = input.url; selectionError = nil
            } catch {
                selected = nil; separatedInput = nil
                selectionError = "Saved vocals are missing, changed, or could not be verified. No generation started; original audio and stems were kept."
            }
        }
        .onChange(of: local.current?.id) { _, _ in journalPage=nil; journalError=nil }
        .onChange(of: sourceURL) { _, _ in
            clipRequest=nil;clipWork?.cancel();clipAuthorized=false
            authorized = false
            if separatedInput != nil { selected = nil; separatedInput = nil }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .audio]) { result in
            switch result {
            case .success(let url):
                authorized = false
                separatedInput = nil
                do {
                    _ = try LocalMediaImportPolicy.fileExtension(url)
                    selected = url; selectionError = nil
                } catch { selected = nil; selectionError = error.localizedDescription }
            case .failure: selectionError = "The selected file could not be opened. No job was started."
            }
        }
    }
    private var clipIntervalValid:Bool {
        guard let start=Double(clipStart),let seconds=Double(clipSeconds) else{return false}
        return start.isFinite && seconds.isFinite && start>=0 && (0.5...10).contains(seconds) && start+seconds<=1800
    }
    private func prepareSeparationClip() {
        guard clipAuthorized, !clipPreparing, clipScene == .active,
              let source=local.retainedSeparationSource,
              let start=Double(clipStart), let seconds=Double(clipSeconds),
              start.isFinite, seconds.isFinite, start>=0, (0.5...10).contains(seconds),start+seconds<=1800 else {
            clipMessage="Enter a valid start and a duration from 0.5 to 10 seconds, then authorize this interval."
            return
        }
        guard let lease=audio.claimProcessing() else {clipMessage="Stop the other audio job first.";return}
        audio.stop();clipPreparing=true;clipMessage="Checking the retained source. Nothing is uploaded."
        let request=UUID();clipRequest=request
        clipWork=Task {
            defer {audio.releaseProcessing(lease);clipPreparing=false;clipWork=nil}
            do {
                let worker=Task.detached {try await SeparationClipHandoff.prepare(source:source,start:start,seconds:seconds)}
                let input=try await withTaskCancellationHandler(operation:{try await worker.value},onCancel:{worker.cancel()})
                try Task.checkCancellation()
                guard clipRequest==request,clipScene == .active,local.retainedSeparationSource==source else {return}
                clipAuthorized=false;clipMessage="Selected short clip ready. Separation has not started."
                clipDestination=input
            } catch is CancellationError {clipMessage="Stopped. Original source and previous results were kept."}
            catch {clipMessage="Could not prepare this interval. The source may have changed, the interval may exceed its audio, or the track/timeline may be unsupported. Original files were kept."}
        }
    }
    private func openSpeaker(_ speaker: String, jobID: UUID, mode: CharacterStudioMode) {
        if local.selectSpeaker(jobID: jobID, speaker: speaker, library: library, audio: audio) {
            audio.stop()
            speakerDestination = mode
        }
    }
    private func loadJournal(_ offset: Int) {
        do { journalPage=try local.journalPage(offset:offset);journalError=nil }
        catch { journalPage=nil;journalError=error.localizedDescription }
    }

}
