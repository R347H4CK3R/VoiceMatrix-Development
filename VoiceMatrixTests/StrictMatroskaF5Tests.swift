#if os(iOS)
import AVFoundation
import CryptoKit
import Foundation
import XCTest
@testable import VoiceMatrix

/// Test host only. No fake model, prebuilt output, external audio or identity claim.
@MainActor
final class StrictMatroskaF5Tests: XCTestCase {
    struct Fixture: Codable {
        struct Turn: Codable { let id: String; let sha256: String; let start: Double; let end: Double }
        let mp4SHA256: String; let turns: [Turn]; let license: String; let identityVerified: Bool
    }
    struct Saved: Codable {
        struct Voice: Codable {
            let id: String
            let referenceSHA256: String
            let manifestSHA256: String
            let previewSHA256: String
            let clipID: UUID
            let clipSHA256: String
            let clipReceiptSHA256: String
            let clipStart: Double
            let clipFrames: Int
            let turn: String
        }
        let phaseOnePID: Int32
        let jobID: UUID
        let attemptID: UUID
        let priorID: String
        let priorReferenceSHA256: String
        let priorManifestSHA256: String
        let source: MatroskaSourceLineage
        let voices: [Voice]
    }

    private func hash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }
    private func root() throws -> URL {
        try XCTUnwrap(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent("strict-f5-proof", isDirectory: true)
    }
    private func libraryRoot(_ root: URL) -> URL { root.appendingPathComponent("Support", isDirectory: true) }
    private func voiceStore(_ root: URL) -> CharacterFolderStore {
        CharacterFolderStore(root: libraryRoot(root).appendingPathComponent("CharacterReferences", isDirectory: true))
    }
    private func makeStudio(_ root: URL) -> LocalVideoStudio {
        LocalVideoStudio(root: root.appendingPathComponent("Jobs", isDirectory: true))
    }
    private func waitUntilIdle(_ busy: () -> Bool, cancel: () -> Void, seconds: Int) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while busy() {
            if Date() >= deadline { cancel(); throw ProbeFailure.timeout }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
    private enum ProbeFailure: Error { case timeout, malformedAudio }

    private func recordPhaseOneFailure(_ root: URL, reason: String, stage: String,
                                       folder: URL, job: LocalVideoStudio.Job?) {
        let allowed = Set(["Received", "Original retained", "Preparing Matroska", "Source retained",
                           "Checking local transcription", "Speaker references ready", "Partial result needs review",
                           "Needs attention", "Paused"])
        let children = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let model: [String: Any] = [
            "schemaVersion": 1, "phase": "phase-one", "reason": reason,
            "stage": allowed.contains(stage) ? stage : "other",
            "originalReceipt": job?.strictMatroska?.original != nil,
            "committedMkvReceipt": job?.strictMatroska?.mkv != nil,
            "committedDerivedReceipt": job?.strictMatroska?.derived != nil,
            "hasStrictJournal": children.contains("strict-matroska-v1.json"),
            "retainedMkvCount": children.filter { $0.hasSuffix(".mkv") }.count,
            "retainedMovCount": children.filter { $0.hasSuffix(".mov") }.count
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: model, options: [.sortedKeys]) else { return }
        try? data.write(to: root.appendingPathComponent("strict-f5-failure.json"), options: .withoutOverwriting)
    }

    private func verifySignal(_ url: URL) throws -> String {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard file.length > 0, file.length <= AVAudioFramePosition(format.sampleRate * 45),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        else { throw ProbeFailure.malformedAudio }
        try file.read(into: buffer)
        guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { throw ProbeFailure.malformedAudio }
        var energy = 0.0
        for index in 0..<Int(buffer.frameLength) {
            let value = Double(channel[index])
            guard value.isFinite else { throw ProbeFailure.malformedAudio }
            energy += value * value
        }
        guard energy / Double(buffer.frameLength) > 1e-8 else { throw ProbeFailure.malformedAudio }
        return try hash(url)
    }

    func testRealStrictSourceSavesTwoReferences() async throws {
        let fm = FileManager.default
        let root = try root()
        XCTAssertFalse(fm.fileExists(atPath: root.path), "A fresh simulator proof root is required.")
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        let fixtures = Bundle(for: Self.self)
        let fixture = try XCTUnwrap(fixtures.url(forResource: "strict-f5-licensed", withExtension: "mp4"))
        let fixtureManifest = try XCTUnwrap(fixtures.url(forResource: "strict-f5-fixture", withExtension: "json"))
        let fixtureInfo = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: fixtureManifest))
        XCTAssertEqual(try hash(fixture), fixtureInfo.mp4SHA256)
        XCTAssertEqual(fixtureInfo.license, "CC-BY-4.0")
        XCTAssertFalse(fixtureInfo.identityVerified)
        XCTAssertEqual(fixtureInfo.turns.count, 2)
        XCTAssertEqual(Set(fixtureInfo.turns.map(\.sha256)).count, 2)
        let collection = try XCTUnwrap(fixtures.url(forResource: "DiagnosticVoices", withExtension: nil))
        let store = voiceStore(root)
        let priorVoices = try await store.importCollection(at: collection)
        XCTAssertEqual(priorVoices.count, 1)
        let prior = try XCTUnwrap(priorVoices.first)
        XCTAssertNil(prior.matroskaReference)
        let priorURL = try await store.referenceURL(id: prior.id)
        let priorManifest = priorURL.deletingLastPathComponent().appendingPathComponent("manifest.json")
        let priorManifestHash = try hash(priorManifest)

        // Seed only the acquired retained original, not analysis, MKV, output or receipts.
        let id = UUID(), attempt = UUID(), now = Date()
        let jobs = root.appendingPathComponent("Jobs", isDirectory: true)
        let folder = jobs.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let original = folder.appendingPathComponent("original.mp4")
        try fm.copyItem(at: fixture, to: original)
        do {
            // The exact production parser distinguishes malformed fixture from inference failure.
            _ = try MP4SampleTable(url: original)
        } catch {
            recordPhaseOneFailure(root, reason: "fixture-rejected-by-production-parser", stage: "Original retained",
                                  folder: folder, job: nil)
            throw error
        }
        let bytes = try original.resourceValues(forKeys: [.fileSizeKey]).fileSize
        let acquisitionURL = try LocalMediaURLPolicy.input("https://www.youtube.com/watch?v=abcdefghijk")
        var job = LocalVideoStudio.Job(id: id, created: now, updated: now, stage: "Original retained",
                                       message: "Licensed diagnostic fixture acquired; network acquisition not under test.")
        job.acquisitionURL = acquisitionURL
        job.originalAcquisitionURL = acquisitionURL
        job.strictMatroska = .init(schemaVersion: 1, attemptID: attempt,
                                   original: .init(file: original.lastPathComponent, sha256: fixtureInfo.mp4SHA256,
                                                   bytes: Int64(try XCTUnwrap(bytes))))
        XCTAssertTrue(job.validStrictMatroska)
        try JSONEncoder().encode(job).write(to: folder.appendingPathComponent("job.json"), options: .withoutOverwriting)

        let library = CharacterLibrary(supportRoot: libraryRoot(root))
        let audio = AudioStore(recordingRoot: root.appendingPathComponent("Recordings", isDirectory: true))
        let speech = SpeechStudio()
        await library.loadAndRefresh()
        let studio = makeStudio(root)
        XCTAssertEqual(studio.current?.id, id)
        studio.resume(library: library, audio: audio, speech: speech)
        try await waitUntilIdle({ studio.busy }, cancel: { studio.cancel() }, seconds: 1800)
        let done = try XCTUnwrap(studio.current)
        if !done.completed {
            let entries = (try? studio.journalPage())?.events ?? []
            recordPhaseOneFailure(root, reason: "production-job-not-completed",
                                  stage: entries.last(where: { $0.stage != "Needs attention" && $0.stage != "Paused" })?.stage ?? done.stage,
                                  folder: folder, job: done)
        }
        XCTAssertTrue(done.completed, studio.notice)
        XCTAssertFalse(audio.processingInUse)
        let source = try XCTUnwrap(done.strictSourceLineage)
        XCTAssertEqual(source.attemptID, attempt)
        XCTAssertEqual(source.acquisitionSHA256, fixtureInfo.mp4SHA256)
        XCTAssertEqual(try hash(original), source.acquisitionSHA256)
        let mkv = try XCTUnwrap(done.strictMatroska?.mkv)
        let derived = try XCTUnwrap(done.strictMatroska?.derived)
        let mov = folder.appendingPathComponent(derived.file)
        XCTAssertEqual(try hash(folder.appendingPathComponent(mkv.file)), source.mkvSHA256)
        XCTAssertEqual(try hash(mov), source.derivedSHA256)
        let ids = try XCTUnwrap(done.speakerVoiceIDs)
        XCTAssertEqual(ids.count, 2, "Two independent turns must survive production grouping and the word check.")
        XCTAssertEqual(Set(ids.values).count, 2)
        let clipStore = SeparationStore(root: root.appendingPathComponent("Clips", isDirectory: true))
        var voices: [Saved.Voice] = []
        for (speaker, id) in ids.sorted(by: { $0.key < $1.key }) {
            let profile = try XCTUnwrap(library.profiles.first(where: { $0.id == id }))
            let lineage = try XCTUnwrap(profile.matroskaReference)
            XCTAssertTrue(profile.validMatroskaReference)
            XCTAssertFalse(profile.trainedModel)
            XCTAssertNil(lineage.separatedClip)
            XCTAssertEqual(lineage.source, source)
            XCTAssertLessThanOrEqual(lineage.requestedDurationSeconds, 10)
            let turn = try XCTUnwrap(fixtureInfo.turns.first(where: {
                lineage.requestedStartSeconds >= $0.start &&
                lineage.requestedStartSeconds + lineage.requestedDurationSeconds <= $0.end
            }))
            let ref = try await store.referenceURL(id: id)
            XCTAssertEqual(try verifySignal(ref), profile.referenceSHA256)
            let actual = try await LocalVideoAudio.extract(source: mov, start: lineage.requestedStartSeconds,
                                                           seconds: lineage.requestedDurationSeconds)
            XCTAssertEqual(actual.wave, try Data(contentsOf: ref))
            let preview = try XCTUnwrap(studio.speakerAssetURL(speaker, preview: true))
            let previewHash = try verifySignal(preview)
            XCTAssertEqual(previewHash, done.speakerAssets?[speaker]?.previewSHA256)
            let retainedSource = try XCTUnwrap(studio.retainedSeparationSource)
            try await studio.verifyRetainedClipSource(retainedSource)
            let clip = try await SeparationClipHandoff.prepare(source: retainedSource,
                start: lineage.requestedStartSeconds, seconds: lineage.requestedDurationSeconds, store: clipStore)
            let persisted = try XCTUnwrap(SeparationClipHandoff.verifiedLineage(clip, store: clipStore))
            XCTAssertEqual(persisted.source, source)
            XCTAssertEqual(persisted.clipSHA256, clip.sha256)
            let manifestHash = try hash(ref.deletingLastPathComponent().appendingPathComponent("manifest.json"))
            voices.append(.init(id: id, referenceSHA256: profile.referenceSHA256, manifestSHA256: manifestHash,
                                previewSHA256: previewHash,
                                clipID: clip.id, clipSHA256: clip.sha256, clipReceiptSHA256: clip.receiptSHA256,
                                clipStart: clip.start, clipFrames: clip.frames, turn: turn.id))
        }
        XCTAssertEqual(Set(voices.map(\.turn)), Set(fixtureInfo.turns.map(\.id)))
        XCTAssertEqual(try hash(priorURL), prior.referenceSHA256)
        XCTAssertEqual(try hash(priorManifest), priorManifestHash)
        let saved = Saved(phaseOnePID: ProcessInfo.processInfo.processIdentifier, jobID: id, attemptID: attempt,
                          priorID: prior.id, priorReferenceSHA256: prior.referenceSHA256,
                          priorManifestSHA256: priorManifestHash, source: source, voices: voices)
        try JSONEncoder().encode(saved).write(to: root.appendingPathComponent("phase-one.json"), options: .withoutOverwriting)
    }

    func testGeneratesNewSpeechAfterProcessRelaunch() async throws {
        let root = try root()
        let saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: root.appendingPathComponent("phase-one.json")))
        let pid = ProcessInfo.processInfo.processIdentifier
        XCTAssertNotEqual(saved.phaseOnePID, pid, "Relaunch must start a distinct hosted app process.")
        let audio = AudioStore(recordingRoot: root.appendingPathComponent("Recordings", isDirectory: true))
        let library = CharacterLibrary(supportRoot: libraryRoot(root))
        let speech = SpeechStudio()
        let studio = makeStudio(root)
        let store = voiceStore(root)
        await library.loadAndRefresh()
        XCTAssertEqual(studio.current?.id, saved.jobID)
        XCTAssertEqual(studio.current?.strictSourceLineage, saved.source)
        XCTAssertTrue(studio.current?.completed == true)
        let retainedJob = root.appendingPathComponent("Jobs", isDirectory: true)
            .appendingPathComponent(saved.jobID.uuidString.lowercased(), isDirectory: true)
        XCTAssertEqual(try hash(retainedJob.appendingPathComponent("original.mp4")), saved.source.acquisitionSHA256)
        let strict = try XCTUnwrap(studio.current?.strictMatroska)
        let original = try XCTUnwrap(strict.original)
        let mkv = try XCTUnwrap(strict.mkv)
        let derived = try XCTUnwrap(strict.derived)
        try await LocalMatroskaWorkflow.validatePublished(jobDirectory: retainedJob, jobID: saved.jobID,
                                                           attemptID: saved.attemptID, acquisition: original,
                                                           mkv: mkv, derived: derived)
        let clipStore = SeparationStore(root: root.appendingPathComponent("Clips", isDirectory: true))
        XCTAssertEqual(Set(library.profiles.map(\.id)), Set(saved.voices.map(\.id) + [saved.priorID]))
        let prior = try await store.referenceURL(id: saved.priorID)
        let manifest = prior.deletingLastPathComponent().appendingPathComponent("manifest.json")
        XCTAssertEqual(try hash(prior), saved.priorReferenceSHA256)
        XCTAssertEqual(try hash(manifest), saved.priorManifestSHA256)
        var generated: [[String: Any]] = []
        let phrases = ["Please close the window and bring the notebook.",
                       "Put the glass of water on the table."]
        XCTAssertEqual(saved.voices.count, phrases.count)
        for (voice, newText) in zip(saved.voices, phrases) {
            let profile = try XCTUnwrap(library.profiles.first(where: { $0.id == voice.id }))
            let ref = try await store.referenceURL(id: voice.id)
            XCTAssertEqual(try hash(ref), voice.referenceSHA256)
            XCTAssertEqual(try hash(ref.deletingLastPathComponent().appendingPathComponent("manifest.json")), voice.manifestSHA256)
            XCTAssertEqual(profile.matroskaReference?.source, saved.source)
            let clip = SeparationClipHandoff.Input(
                id: voice.clipID, url: clipStore.root.appendingPathComponent("Clip-" + voice.clipID.uuidString)
                    .appendingPathComponent("clip.wav"), sha256: voice.clipSHA256,
                receiptSHA256: voice.clipReceiptSHA256, start: voice.clipStart, frames: voice.clipFrames)
            let persisted = try XCTUnwrap(SeparationClipHandoff.verifiedLineage(clip, store: clipStore))
            XCTAssertEqual(persisted.source, saved.source)
            XCTAssertEqual(persisted.clipSHA256, voice.clipSHA256)
            library.selectedID = voice.id
            library.speak(newText, audio: audio, studio: speech)
            try await waitUntilIdle({ library.busy }, cancel: { library.cancel() }, seconds: 600)
            let output = try XCTUnwrap(library.output, library.message)
            XCTAssertEqual(library.outputCharacterID, voice.id, library.message)
            XCTAssertEqual(library.outputReferenceHash, voice.referenceSHA256)
            let outputHash = try verifySignal(output)
            XCTAssertNotEqual(outputHash, voice.previewSHA256)
            XCTAssertNotEqual(outputHash, voice.referenceSHA256)
            let owner = try await library.beginLocalGeneration()
            defer { library.endLocalGeneration(owner) }
            let asr = OnDeviceTranscription(bundle: Bundle.main.url(forResource: "ParakeetASR", withExtension: nil))
            try await asr.authorize()
            let recognized = try await asr.transcribe(output)
            let wer = LocalStudioEvidence.wordErrorRate(expected: newText, actual: recognized)
            XCTAssertLessThanOrEqual(wer, 0.1)
            XCTAssertEqual(asr.lastEvidence?.inputSHA256, outputHash)
            generated.append(["voiceID": voice.id, "referenceSHA256": voice.referenceSHA256,
                              "manifestSHA256": voice.manifestSHA256, "clipSHA256": voice.clipSHA256,
                              "previewSHA256": voice.previewSHA256, "speechSHA256": outputHash, "wordErrorRate": wer])
        }
        XCTAssertFalse(audio.processingInUse)
        XCTAssertEqual(try hash(prior), saved.priorReferenceSHA256)
        XCTAssertEqual(try hash(manifest), saved.priorManifestSHA256)
        XCTAssertEqual(Set(library.profiles.map(\.id)), Set(saved.voices.map(\.id) + [saved.priorID]))
        let info: [String: Any] = ["metadataOnly": true, "phaseOnePID": saved.phaseOnePID, "phaseTwoPID": pid,
                                   "jobID": saved.jobID.uuidString, "attemptID": saved.attemptID.uuidString,
                                   "originalSHA256": saved.source.acquisitionSHA256, "mkvSHA256": saved.source.mkvSHA256,
                                   "derivedSHA256": saved.source.derivedSHA256,
                                   "distinctFixtureTurns": Set(saved.voices.map(\.turn)).count,
                                   "generated": generated, "priorVoicePreserved": true, "identityVerified": false,
                                   "physicalDeviceVerified": false, "liveURLVerified": false]
        try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]).write(
            to: root.appendingPathComponent("strict-f5-report.json"), options: .withoutOverwriting)
    }
}
#endif
