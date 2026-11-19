import Foundation
import AVFoundation
import Combine
import CryptoKit

@MainActor final class LocalVideoStudio: ObservableObject {
    typealias Event = LocalStudioJournal.Event
    struct Similarity: Codable {
        let referenceFile: String
        let previewFile: String
        let measured: Date
        let report: SpeakerSimilarityService.Report
    }
    /// Stored only after import/reuse succeeds; hashes bind this speaker's accepted pair.
    struct SpeakerAssets: Codable {
        let voiceID: String
        let referenceFile: String
        let referenceSHA256: String
        let previewFile: String
        let previewSHA256: String
    }
    struct StrictMatroska: Codable {
        let schemaVersion: Int
        let attemptID: UUID
        var original: LocalMediaAcquisition.Result?
        var mkv: LocalMediaAcquisition.Result?
        var derived: LocalMediaAcquisition.Result?
    }
    struct Job: Codable, Identifiable {
        let id: UUID
        let created: Date
        var updated: Date
        var stage: String
        var message: String
        var originalAcquisitionURL: URL?
        var acquisitionURL: URL?
        var strictMatroska: StrictMatroska?
        var sourceFile: String?
        var sourceSHA256: String?
        var analysisFile: String?
        var analysisSHA256: String?
        var visualEvidence: LocalVisualEvidence.Report?
        var similarity: Similarity?
        var referenceFile: String?
        var previewFile: String?
        var voiceID: String?
        var speakerVoiceIDs: [String:String]?
        var speakerAssets: [String:SpeakerAssets]?
        var speakerOutcomes: [String:String]?
        var qualityPolicyVersions: [String:Int]?
        var completed = false
        var events: [Event] = []

        var validStrictMatroska: Bool {
            guard let state = strictMatroska else { return true }
            func matches(_ media: LocalMediaAcquisition.Result, filename: String) -> Bool {
                media.file.range(of: filename, options: .regularExpression) != nil &&
                media.sha256.utf8.count == 64 &&
                media.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil &&
                (1...LocalMediaURLPolicy.maximumBytes).contains(media.bytes)
            }
            guard state.schemaVersion == 1, let acquisitionURL,
                  (try? LocalMediaURLPolicy.input(acquisitionURL.absoluteString)) == acquisitionURL else { return false }
            if let original = state.original,
               !matches(original, filename: "^[A-Za-z0-9_-]{1,128}[.]mp4$") { return false }
            if state.mkv == nil && state.derived == nil {
                return sourceFile == nil && sourceSHA256 == nil && !completed && analysisFile == nil &&
                    analysisSHA256 == nil && visualEvidence == nil && similarity == nil &&
                    referenceFile == nil && previewFile == nil && voiceID == nil &&
                    speakerVoiceIDs == nil && speakerAssets == nil && speakerOutcomes == nil &&
                    qualityPolicyVersions == nil
            }
            guard let original = state.original, let mkv = state.mkv, let derived = state.derived,
                  matches(mkv, filename: "^strict-[a-f0-9-]{36}[.]mkv$"),
                  matches(derived, filename: "^strict-[a-f0-9-]{36}[.]mov$"),
                  Set([original.sha256, mkv.sha256, derived.sha256]).count == 3 else { return false }
            return sourceFile == derived.file && sourceSHA256 == derived.sha256
        }

        // Do not compare a new speaker/reference against an earlier attempt's audio.
        var matchingPreviewFile: String? {
            guard let referenceFile, let previewFile,
                  referenceFile.hasPrefix("reference-"), previewFile.hasPrefix("preview-"),
                  referenceFile.dropFirst("reference-".count) == previewFile.dropFirst("preview-".count)
            else { return nil }
            return previewFile
        }
        var matchingSimilarity: Similarity? {
            guard let similarity, similarity.referenceFile == referenceFile,
                  similarity.previewFile == matchingPreviewFile else { return nil }
            let r=similarity.report
            guard r.schemaVersion == 1, r.modelRevision == SpeakerSimilarityService.modelRevision,
                  r.algorithm == "bundled-raw256-l2-cosine-v1", !r.likenessVerified, !r.identityVerified,
                  r.cosineSimilarity.isFinite, (-1...1).contains(r.cosineSimilarity),
                  r.referenceSeconds.isFinite, (3...30).contains(r.referenceSeconds),
                  r.generatedSeconds.isFinite, (3...30).contains(r.generatedSeconds),
                  r.referenceSHA256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
                  r.generatedSHA256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { return nil }
            return similarity
        }
        mutating func selectReference(_ file: String) {
            referenceFile = file
            previewFile = nil
            similarity = nil
        }
    }
    @Published private(set) var current: Job?
    @Published private(set) var history: [Job] = []
    @Published private(set) var historyReadFailures = 0
    @Published private(set) var busy = false
    @Published private(set) var notice = "Import an authorized local video or recording. Processing runs on this iPhone. URL acquisition contacts only the source website."
    private let root: URL
    private let transcriber: OnDeviceTranscription
    private let f5Bundle: URL?
    private let speakerBundle: URL?
    private let engine = F5ReferenceEngine(idleRetention: .zero)
    private let similarityService = SpeakerSimilarityService()
    private var operation: Task<Void, Never>?
    private var active = true
    private var runToken = UUID()
    // Natural speech budget for the 3–30 second embedding diagnostic; actual audio bounds
    // are still checked. Do not pad or loop short output to manufacture evidence.
    private let previewText = "Please open the blue notebook and write down these instructions. Close the window, bring a glass of water, and place the book on the table."
    init(root: URL? = nil,
         asrBundle: URL? = Bundle.main.url(forResource: "ParakeetASR", withExtension: nil),
         f5Bundle: URL? = Bundle.main.url(forResource: "F5TTS", withExtension: nil),
         speakerBundle: URL? = Bundle.main.url(forResource: "Diarization", withExtension: nil)) {
        self.transcriber = OnDeviceTranscription(bundle: asrBundle)
        self.f5Bundle = f5Bundle; self.speakerBundle = speakerBundle
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LocalVideoStudio", isDirectory: true)
        reloadHistory()
        current = history.first
        if current?.completed == false { notice = "Previous work was retained. Resume to continue while this app is open." }
    }
    var reference: URL? { current?.referenceFile.map { folder.appendingPathComponent($0) } }
    var preview: URL? { current?.matchingPreviewFile.map { folder.appendingPathComponent($0) } }
    private var folder: URL { root.appendingPathComponent(current!.id.uuidString.lowercased(), isDirectory: true) }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func reloadHistory() {
        var rejected = 0
        func unreadable() -> Job? { rejected += 1; return nil }
        history = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []).compactMap { url in
            guard UUID(uuidString: url.lastPathComponent) != nil else { return nil }
            guard let data = try? LocalStudioSnapshot.read(folder: url),
                  let job = try? JSONDecoder().decode(Job.self, from: data), job.id.uuidString.lowercased() == url.lastPathComponent,
                  job.created.timeIntervalSince1970.isFinite, job.updated.timeIntervalSince1970.isFinite else { return unreadable() }
            func safe(_ value: String?) -> Bool { value == nil || (value!.range(of: "^[a-zA-Z0-9_-]+(?:\\.[a-zA-Z0-9_-]+)*$", options: .regularExpression) != nil) }
            guard safe(job.sourceFile), safe(job.analysisFile), safe(job.referenceFile), safe(job.previewFile) else { return unreadable() }
            if let input = job.acquisitionURL, (try? LocalMediaURLPolicy.input(input.absoluteString)) == nil { return unreadable() }
            guard job.validStrictMatroska else { return unreadable() }
            return job
        }.sorted { $0.created > $1.created }
        historyReadFailures = rejected
    }
    private func update(_ stage: String, _ text: String, log: Bool = true, completed: Bool? = nil) throws {
        guard var value = current else { return }
        value.updated = Date(); value.stage = stage; value.message = text
        // Completion must remain retryable if either durable write fails.
        if let completed { value.completed = completed }
        // Every real activity update is durable, including byte counters. UI refresh never calls update.
        let event=LocalStudioJournal.sanitized(Event(id:UUID(),time:value.updated,stage:stage,message:text))
        try LocalStudioJournal.append(event,folder:folder,legacy:value.events)
        if log { value.events.append(event); value.events = Array(value.events.suffix(160)) }
        let snapshot = try LocalStudioSnapshot.encode(value, events: value.events) { $0.events = $1 }
        try snapshot.data.write(to: folder.appendingPathComponent("job.json"), options: .atomic)
        current = snapshot.value; notice = text
    }
    func verifiedMKVExport() async -> URL? {
        guard !busy, let job = current, let digest = job.sourceSHA256 else { return nil }
        let directory = root.appendingPathComponent(job.id.uuidString.lowercased(), isDirectory: true)
        let export: URL?
        if let strict = job.strictMatroska {
            #if os(iOS)
            guard job.validStrictMatroska, let original = strict.original,
                  let mkv = strict.mkv, let derived = strict.derived else { return nil }
            do {
                try await LocalMatroskaWorkflow.validatePublished(jobDirectory: directory, jobID: job.id,
                                                                  attemptID: strict.attemptID, acquisition: original,
                                                                  mkv: mkv, derived: derived)
                export = directory.appendingPathComponent(mkv.file)
            } catch { return nil }
            #else
            return nil
            #endif
        } else {
            export = try? await LocalMediaAcquisition.verifiedMatroska(folder: directory, sourceSHA256: digest)
        }
        guard !Task.isCancelled, current?.id == job.id, current?.sourceSHA256 == digest, !busy else { return nil }
        return export
    }
    var retainedSeparationSource: SeparationClipHandoff.Source? {
        guard !busy, let job=current, job.validStrictMatroska, let name=job.sourceFile, let sha=job.sourceSHA256,
              name.range(of:"^[a-zA-Z0-9_-]+(?:\\.[a-zA-Z0-9_-]+)*$",options:.regularExpression) != nil,
              sha.range(of:"^[0-9a-f]{64}$",options:.regularExpression) != nil else {return nil}
        return SeparationClipHandoff.Source(jobID:job.id,url:folder.appendingPathComponent(name),sha256:sha)
    }
    func journalPage(offset: Int = 0) throws -> LocalStudioJournal.Page {
        guard offset>=0,let current else { throw LocalStudioJournal.Failure.unsafe }
        let file=folder.appendingPathComponent(LocalStudioJournal.filename)
        if !FileManager.default.fileExists(atPath:file.path) {
            // Read-only legacy compatibility; do not claim already-lost events exist.
            let entries=Array(current.events.dropFirst(offset).prefix(100))
            return LocalStudioJournal.Page(events:entries.map(LocalStudioJournal.sanitized),offset:offset,total:current.events.count)
        }
        return try LocalStudioJournal.read(folder:folder,offset:offset)
    }
    func visualFrameData(_ frame: LocalVisualEvidence.Frame) -> Data? {
        guard let report=current?.visualEvidence, report.sourceSHA256 == current?.sourceSHA256,
              report.frames.contains(where: { $0.id == frame.id && $0.sha256 == frame.sha256 }) else { return nil }
        return try? LocalVisualEvidence.frameData(frame,folder:folder)
    }
    /// Read and hash bounded current snapshots before displaying a recorded metric.
    /// This is not a hostile-filesystem sandbox or a claim about subsequent edits.
    func validatedSimilarity() -> Similarity? {
        guard !busy, let evidence=current?.matchingSimilarity else { return nil }
        do {
            for (name,expected) in [(evidence.referenceFile,evidence.report.referenceSHA256),(evidence.previewFile,evidence.report.generatedSHA256)] {
                guard name.range(of:"^(?:reference|preview)-[A-Za-z0-9_-]+\\.wav$",options:.regularExpression) != nil else { return nil }
                let url=folder.appendingPathComponent(name)
                let v=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard v.isRegularFile == true,v.isSymbolicLink != true,(44...4_194_304).contains(v.fileSize ?? 0) else { return nil }
                let bytes=try Data(contentsOf:url)
                guard bytes.count == v.fileSize,Self.hash(bytes) == expected else { return nil }
            }
            return evidence
        } catch { return nil }
    }
    /// Explicit navigation handoff only; never starts generation or changes retained files.
    func selectSpeaker(jobID: UUID, speaker: String, library: CharacterLibrary, audio: AudioStore) -> Bool {
        guard !busy, active, !library.busy,
              !audio.processingInUse, !audio.microphoneInUse,
              current?.id == jobID else { return false }
        guard let assets = current?.speakerAssets?[speaker],
              validatedSpeakerAssetURL(speaker, preview: false) != nil else { return false }
        guard let voiceID = LocalSpeakerHandoff.voiceID(expected: assets.voiceID,
                referenceSHA256: assets.referenceSHA256,
                profiles: library.profiles.map { .init(id: $0.id, referenceSHA256: $0.referenceSHA256) }) else {
            notice = "This speaker's matching saved voice is missing, changed or ambiguous. Your current selection and retained files were kept."
            return false
        }
        library.selectedID = voiceID
        return true
    }
    /// Validate both retained files on explicit playback, not on every live-log refresh.
    /// Private app storage is trusted against concurrent hostile replacement after this read.
    func speakerAssetURL(_ speaker: String, preview: Bool) -> URL? {
        guard !busy else { return nil }
        return validatedSpeakerAssetURL(speaker, preview: preview)
    }
    /// Shared receipt verification for explicit playback and resume. Called once per saved
    /// speaker during a run, never on each log refresh; does not mutate retained assets.
    private func validatedSpeakerAssetURL(_ speaker: String, preview: Bool) -> URL? {
        guard let assets=current?.speakerAssets?[speaker],
              current?.speakerVoiceIDs?[speaker] == assets.voiceID else {
            notice="No accepted per-speaker audio receipt is available. Older jobs keep their existing files and library voices."
            return nil
        }
        guard assets.referenceFile.range(of:"^reference-[A-Za-z0-9_-]+\\.wav$",options:.regularExpression) != nil,
              assets.previewFile == "preview-" + assets.referenceFile.dropFirst("reference-".count) else {
            notice="Speaker audio pairing is invalid. Retained files were not changed."
            return nil
        }
        do {
            for (name,expected) in [(assets.referenceFile,assets.referenceSHA256),(assets.previewFile,assets.previewSHA256)] {
                guard expected.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil else { throw LocalError.preview }
                let url=folder.appendingPathComponent(name)
                let values=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard values.isRegularFile == true,values.isSymbolicLink != true,(44...4_194_304).contains(values.fileSize ?? 0) else { throw LocalError.preview }
                let bytes=try Data(contentsOf:url)
                guard bytes.count == values.fileSize,Self.hash(bytes) == expected else { throw LocalError.preview }
            }
            notice="Verified retained audio files for speaker " + speaker + ". Word checks passed when saved; likeness and identity are unverified."
            return folder.appendingPathComponent(preview ? assets.previewFile : assets.referenceFile)
        } catch {
            notice="Speaker audio is missing or changed; playback was stopped. The retained files and library voices were not deleted."
            return nil
        }
    }
    private func recordSpeakerAssets(_ speaker: String, voiceID: String, referenceSHA256: String, previewSHA256: String) throws {
        guard let referenceFile=current?.referenceFile,let previewFile=current?.matchingPreviewFile,
              current?.speakerVoiceIDs?[speaker] == voiceID else { throw LocalError.preview }
        if current?.speakerAssets == nil { current?.speakerAssets=[:] }
        current?.speakerAssets?[speaker]=SpeakerAssets(voiceID:voiceID,referenceFile:referenceFile,referenceSHA256:referenceSHA256,previewFile:previewFile,previewSHA256:previewSHA256)
    }
    func selectHistory(_ job: Job) { guard !busy else { return }; current = job; notice = job.message }
    func setActive(_ value: Bool) { active = value; if !value, busy { cancel() } }
    func memoryWarning() {
        guard busy else { return }
        operation?.cancel()
        try? update("Stopping for memory", "iOS reported memory pressure. Stopping at a safe boundary and retaining source/output files.")
    }
    func thermalChanged() {
        guard busy, ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical else { return }
        operation?.cancel()
        try? update("Stopping for temperature", "iPhone temperature is high. Let it cool before resuming; retained files are kept.")
    }
    func cancel() { guard busy else { return }; operation?.cancel(); try? update("Stopping", "Stopping at a safe boundary. Source and completed outputs are retained.") }
    func startURL(_ text: String, authorized: Bool, library: CharacterLibrary, audio: AudioStore, speech: SpeechStudio) {
        do {
            _ = try LocalMediaURLPolicy.input(text)
            guard let original = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw LocalMediaURLPolicy.Failure.url }
            start(original, authorized: authorized, library: library, audio: audio, speech: speech)
        }
        catch { notice = LocalMediaURLPolicy.Failure.url.errorDescription! }
    }
    func start(_ source: URL, authorized: Bool, library: CharacterLibrary, audio: AudioStore, speech: SpeechStudio, referenceInput: SeparationStore.ReferenceInput? = nil, strictForNewLink: Bool = true) {
        guard referenceInput == nil || (source.isFileURL && referenceInput?.url == source) else { return }
        guard authorized, !busy, active else { return }
        guard !audio.processingInUse, !audio.microphoneInUse else { notice = "Stop the other recording or speech job first."; return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let free = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage ?? 0
            let retained = try LocalMediaAcquisition.retainedBytes(root: root)
            guard free >= 800_000_000, retained < 2_000_000_000 else { throw LocalError.storage }
            let now = Date()
            current = Job(id: UUID(), created: now, updated: now, stage: "Received", message: "Source selected; preparing retained acquisition.")
            if !source.isFileURL {
                current?.acquisitionURL = try LocalMediaURLPolicy.input(source.absoluteString)
                current?.originalAcquisitionURL = source
                #if os(iOS)
                if strictForNewLink { current?.strictMatroska = StrictMatroska(schemaVersion: 1, attemptID: UUID()) }
                #endif
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
            try update("Received", source.isFileURL ? "App received the selected local media. Nothing is uploaded." : "App received the URL. Downloading directly from its website; no laptop or conversion service. The private URL is not shown in this log.")
            run(source: source.isFileURL ? source : nil, library: library, audio: audio, speech: speech, referenceInput: referenceInput)
        } catch { notice = "Could not start a local job. Check free storage; existing voices were kept." }
    }
    var freshAcquisitionURL: URL? {
        guard let job = current else { return nil }
        return LocalMediaURLPolicy.freshAcquisitionInput(original: job.originalAcquisitionURL,
            retained: job.acquisitionURL, completed: job.completed, hasSource: job.sourceFile != nil)
    }
    /// Explicit confirmation is bound to the selected job. Existing receipt/tracks are untouched;
    /// start creates a distinct UUID folder and repeats normal storage, source and processing gates.
    func retryAcquisition(jobID: UUID, authorized: Bool, library: CharacterLibrary, audio: AudioStore, speech: SpeechStudio) {
        guard authorized, !busy, active, current?.id == jobID, let source = freshAcquisitionURL else { return }
        start(source, authorized: true, library: library, audio: audio, speech: speech,
              strictForNewLink: current?.strictMatroska != nil)
    }
    func resume(library: CharacterLibrary, audio: AudioStore, speech: SpeechStudio) {
        guard !busy, active, let job = current, job.validStrictMatroska, !job.completed, job.sourceFile != nil || job.acquisitionURL != nil else { return }
        run(source: nil, library: library, audio: audio, speech: speech)
    }
    private enum LocalError: LocalizedError {
        case storage, source, candidate, preview, engine, thermal
        var errorDescription: String? {
            switch self {
            case .storage: return "Free at least 800 MB. Retained local jobs have a 2 GB admission limit; no old files were deleted."
            case .source: return "The retained source is missing, changed or unsupported. Existing voices were kept."
            case .candidate: return "No acceptable reference was found. Speaker timing is not proof of music-free speech or character identity."
            case .preview: return "Three previews failed the spoken-word check. References and completed previews were retained for review."
            case .engine: return "The bundled F5 engine is unavailable. A complete app build is required; no network fallback was used."
            case .thermal: return "iPhone temperature is too high for this job. Let it cool, then Resume."
            }
        }
    }
    private func check() throws {
        try Task.checkCancellation()
        if ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical { throw LocalError.thermal }
    }
    #if os(iOS)
    private func prepareStrictMatroska(jobFolder: URL, token: UUID) async throws {
        guard let job = current, job.validStrictMatroska, var strict = job.strictMat…6088 tokens truncated…pt evidence was kept; trying another candidate.")
                            continue
                        }
                        try check(); previews += 1
                        try candidate.record(.generating,reason:"Generating bounded preview",referenceSHA256:referenceDigest,directory:jobFolder)
                        try update("Generating preview", "Loading the bundled F5 engine and generating preview \(previews) of at most 3 for speaker \(speaker.speaker). No laptop or server is used.")
                        let preview = jobFolder.appendingPathComponent("preview-" + attempt + ".wav")
                        try await engine.load(localBundle: bundle)
                        do { try await engine.speak(text: previewText, referenceAudio: reference, referenceText: transcript, destination: preview, preserveIncomplete: true) { [weak self] part, total in
                            Task { @MainActor in guard let self, self.runToken == run, self.busy, self.current?.stage == "Generating preview", self.current?.referenceFile == reference.lastPathComponent else { return }; try? self.update("Generating preview", "Generating speech part \(part) of \(total).", log: false) }
                        }
                        } catch F5ChunkError.unusableGeneratedAudio {
                            await engine.finishRequest(keepWarm: false)
                            try check()
                            try candidate.record(.generationRejected,reason:"Generated audio was silent, too short or nonfinite",referenceSHA256:referenceDigest,directory:jobFolder)
                            try update("Preview rejected", "Generated audio was unusable. Reference and partial preview were retained; trying another candidate.")
                            if previews >= 3 { break }; continue
                        }
                        await engine.finishRequest(keepWarm: false)
                        try candidate.record(.verifying,reason:"Generated preview pending word check",referenceSHA256:referenceDigest,directory:jobFolder)
                        try update("Verifying preview", "Checking the generated words locally. This does not verify likeness.")
                        let recognized: String
                        do { recognized = try await transcriber.transcribe(preview) }
                        catch OnDeviceTranscription.Failure.noSpeech {
                            try candidate.record(.previewNoSpeech,reason:"No speech recognized in generated preview",referenceSHA256:referenceDigest,directory:jobFolder)
                            try update("Preview rejected", "No preview speech was recognized. Preview and reference were retained.")
                            if previews >= 3 { break }; continue
                        }
                        guard let previewEvidence = transcriber.lastEvidence else { throw LocalError.preview }
                        try JSONEncoder().encode(previewEvidence).write(to: jobFolder.appendingPathComponent("preview-asr-evidence-" + attempt + ".json"), options: .atomic)
                        guard LocalStudioEvidence.wordErrorRate(expected: previewText, actual: recognized) <= 0.1 else {
                            try candidate.record(.previewWordsRejected,reason:"Preview exceeded the unchanged spoken-word error gate",referenceSHA256:referenceDigest,previewSHA256:previewEvidence.inputSHA256,directory:jobFolder)
                            try update("Preview rejected", "Spoken words did not pass. This preview is retained but will not be imported.")
                            if previews >= 3 { break }; continue
                        }
                        try check()
                        // Changed preview bytes must fail the job, not become an optional diagnostic failure.
                        let values=try preview.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                        guard values.isRegularFile == true, values.isSymbolicLink != true,
                              (44...4_194_304).contains(values.fileSize ?? 0) else { throw LocalError.preview }
                        let generated=try Data(contentsOf:preview)
                        guard generated.count == values.fileSize, Self.hash(generated) == previewEvidence.inputSHA256 else { throw LocalError.preview }
                        current?.previewFile = preview.lastPathComponent
                        // Diagnostic only: never promote a cosine score into identity/likeness approval.
                        try update("Measuring speaker similarity", "Comparing the retained reference and word-checked preview locally; not identity or likeness verification.")
                        do {
                            guard let speakerBundle else { throw LocalSpeakerDiarization.Failure.bundleUnavailable }
                            let report=try await similarityService.compare(referenceWAV:clip.wave,generatedWAV:generated,bundle:speakerBundle) { [weak self] message in
                                Task { @MainActor in
                                    guard let self,self.runToken == run,self.busy,self.current?.stage == "Measuring speaker similarity",self.current?.referenceFile == reference.lastPathComponent else { return }
                                    try? self.update("Measuring speaker similarity",message,log:false)
                                }
                            }
                            try check()
                            guard report.referenceSHA256 == Self.hash(clip.wave), report.generatedSHA256 == previewEvidence.inputSHA256 else { throw LocalError.preview }
                            let evidence=Similarity(referenceFile:reference.lastPathComponent,previewFile:preview.lastPathComponent,measured:Date(),report:report)
                            try JSONEncoder().encode(evidence).write(to:jobFolder.appendingPathComponent("similarity-" + attempt + ".json"),options:.atomic)
                            current?.similarity=evidence
                            try update("Speaker similarity recorded", "Saved a hash-bound numeric diagnostic. No identity or likeness acceptance threshold was applied.")
                        } catch let error as LocalError { throw error }
                        catch {
                            try check()
                            current?.similarity=nil
                            let reason: String
                            switch error as? SpeakerSimilarityService.Failure {
                            case .resourceBound: reason="A clip is outside the 3–30 second or 4 MiB diagnostic limit."
                            case .invalidWave: reason="A clip is not suitable nonsilent mono PCM16 audio."
                            case .conversion: reason="Local sample-rate conversion did not complete."
                            case .embedding: reason="The bundled speaker model did not return a valid embedding."
                            case .busy: reason="Another similarity comparison is already running."
                            case nil: reason="The local model or comparison could not complete."
                            }
                            try update("Similarity unavailable", reason + " The word-checked reference remains usable; identity and likeness remain unverified.")
                        }
                        if let existing = library.profiles.first(where: { $0.referenceSHA256 == Self.hash(clip.wave) && $0.referenceText == transcript }) {
                            library.selectedID = existing.id
                            current?.voiceID = existing.id
                            current?.speakerVoiceIDs?[speaker.speaker] = existing.id
                            try candidate.record(.reused,reason:"Existing reference reused; likeness unverified",referenceSHA256:referenceDigest,previewSHA256:previewEvidence.inputSHA256,voiceID:existing.id,directory:jobFolder)
                            try recordSpeakerAssets(speaker.speaker, voiceID: existing.id, referenceSHA256: Self.hash(clip.wave), previewSHA256: previewEvidence.inputSHA256)
                            current?.qualityPolicyVersions?[speaker.speaker] = LocalSoundQualityPolicy.version
                            current?.speakerOutcomes?[speaker.speaker] = "Saved reference; word check passed; likeness unverified"
                            imported = true; saved += 1
                            try update("Reference ready", "Reused \(existing.name) (ID \(existing.id)). Library now contains \(library.profiles.count) voices. Preview and screening evidence were retained; likeness is not verified.")
                            break
                        }
                        let id = "local-" + current!.id.uuidString.lowercased() + "-" + speaker.speaker.lowercased()
                        let collection = jobFolder.appendingPathComponent("collection-" + attempt, isDirectory: true)
                        let voiceFolder = collection.appendingPathComponent(id, isDirectory: true)
                        try FileManager.default.createDirectory(at: voiceFolder, withIntermediateDirectories: true)
                        let metadata: [String: Any] = ["id": id, "name": "Unidentified speaker " + speaker.speaker + " " + String(current!.id.uuidString.prefix(6)), "source": "User-authorized local media SHA256 " + expectedHash, "permission": "User affirmed source-use authorization in the local studio", "referenceText": transcript, "schemaVersion": 1, "kind": "f5-reference", "engine": "F5TTS_v1_Base", "referenceFile": "reference.wav", "referenceSHA256": Self.hash(clip.wave), "trainedModel": false, "categories": ["Local", "Unidentified", "Preview-only"], "referenceBytes": clip.wave.count, "seconds": clip.seconds]
                        try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]).write(to: voiceFolder.appendingPathComponent("manifest.json"), options: .atomic)
                        try clip.wave.write(to: voiceFolder.appendingPathComponent("reference.wav"), options: .atomic)
                        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "voices": [["id": id, "folder": id]]]).write(to: collection.appendingPathComponent("collection.json"), options: .atomic)
                        try update("Importing", "Atomically validating and registering the preview-only reference on this iPhone.")
                        try await library.importLocalGeneratedCollection(collection, owner: libraryOwner!)
                        guard let savedProfile = library.profiles.first(where: { $0.id == id }) else { throw LocalError.candidate }
                        try candidate.record(.saved,reason:"Reference imported; likeness unverified",referenceSHA256:referenceDigest,previewSHA256:previewEvidence.inputSHA256,voiceID:id,directory:jobFolder)
                        current?.voiceID = id
                        current?.speakerVoiceIDs?[speaker.speaker] = id
                        try recordSpeakerAssets(speaker.speaker, voiceID: id, referenceSHA256: Self.hash(clip.wave), previewSHA256: previewEvidence.inputSHA256)
                        current?.qualityPolicyVersions?[speaker.speaker] = LocalSoundQualityPolicy.version
                        current?.speakerOutcomes?[speaker.speaker] = "Saved reference; word check passed; likeness unverified"
                        imported = true; saved += 1
                        try update("Reference ready", "Added \(savedProfile.name) (ID \(savedProfile.id)). Library now contains \(library.profiles.count) voices; previous voices were kept. Screening and word checks passed, but character identity, separation and RVC training are not verified.")
                        break
                    }
                    if !imported {
                        unresolved += 1
                        current?.speakerOutcomes?[speaker.speaker] = "No candidate passed all screening and spoken-word checks"
                        try update("Speaker needs review", "Speaker \(speaker.speaker) has no accepted reference. Sources and attempts were retained; continuing other groups.")
                    }
                }
                try update(unresolved == 0 ? "Speaker references ready" : "Partial result needs review", "Saved or reused \(saved) speaker references; \(unresolved) groups need review. Likeness, character identity, music separation and RVC training are not verified.", completed: saved > 0 && unresolved == 0)
                return
            } catch {
                await engine.finishRequest(keepWarm: false)
                let canceled = error is CancellationError || Task.isCancelled
                let pauseMessage = current?.acquisitionURL != nil ? "Acquisition or processing paused. Completed tracks and partial attempts are kept. Resume reuses verified completed files; incomplete downloads restart without unsafe byte appending." : current?.sourceFile == nil ? "Source copy interrupted. Partial data was kept; choose the source again to start a new job." : "Paused. Retained source and completed outputs are safe. Resume while this app is open."
                let message = canceled ? pauseMessage : (error as? LocalizedError)?.errorDescription ?? "Local processing could not finish. Retained files and existing voices were kept."
                do { try update(canceled ? "Paused" : "Needs attention", message) }
                catch { notice = "Could not save the latest status. Existing files were kept; check iPhone storage." }
            }
        }
    }
}
