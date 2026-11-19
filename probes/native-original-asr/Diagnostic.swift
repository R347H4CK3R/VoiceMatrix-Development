import AVFoundation
import CryptoKit
import Foundation

/// Exact application recognizer against its local vendored SDK. Evaluation labels are never inference inputs.
@main struct OriginalFrontendASRDiagnostic {
    static let fixtureCap = 8_388_608
    static let expectedSourcesHash = "00d13f6b6054551da772c5566eb7f65ade4017ac58e5132cef7931720c83f9b8"
    static let modelRevision = "f2f43eaa239d1ea45191c2a2d5bd0f980dae1b1f"
    static let originalNVIDIARevision = "541d1f99c6b0c3cd0b11a95167540bb8edefd82b"
    static let nemoSourceRevision = "abddc854389e9efcaf38c605ef66af675fc5f8f7"

    struct HumanSource: Decodable {
        let id, referenceText, sourceSHA256, license, datasetRevision: String
        let offset, speaker_id, sourceBytes, sourceFrames: Int
    }
    struct HumanManifest: Decodable {
        let schemaVersion: Int
        let cases: [HumanCase]
    }
    struct HumanCase: Decodable {
        let id, mode, file, sha256, expected, sourceSHA256, corpusFLACSHA256: String
        let bytes: Int
    }
    struct Speech {
        let id, mode, digest, expected: String
        let url: URL
        let maximumWER: Double
    }
    struct Result: Encodable {
        let id, mode, inputSHA256: String
        let expected, recognized, error: String?
        let wordErrorRate: Double?
        let tokenEvidence: OnDeviceTranscription.Evidence?
        let successActivityCount: Int
        let elapsedSeconds: Double
        let accepted: Bool
    }
    struct Report: Encodable {
        let schemaVersion = 1
        let status: String
        let sourceCommit: String
        let modelsRevision = BundledASRAssets.revision
        let resourceLockSHA256 = BundledASRAssets.lockSHA256
        let frontend = "Native Double NeMo 2.3.1 semantics with pinned original NVIDIA frontend buffers"
        let frontendSourceRevision = OriginalFrontendASRDiagnostic.nemoSourceRevision
        let originalModelRevision = OriginalFrontendASRDiagnostic.originalNVIDIARevision
        let humanSourcePinSHA256 = OriginalFrontendASRDiagnostic.expectedSourcesHash
        let humanInputManifestSHA256: String
        let cancelledRequestRejected: Bool
        let retryAfterCancellationPassed: Bool
        let results: [Result]
        let fullLocalPipelineVerified = false
        let physicalDeviceVerified = false
    }
    enum Failure: Error { case arguments, fixtureIdentity, cancellation, acceptance }

    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func readBounded(_ url: URL, max: Int, exact: Int? = nil) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (1...max).contains(size), exact == nil || exact == size
        else { throw Failure.fixtureIdentity }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var bytes = Data(capacity: size)
        while bytes.count <= max {
            let want = min(65_536, max + 1 - bytes.count)
            guard let block = try handle.read(upToCount: want), !block.isEmpty else { break }
            bytes.append(block)
        }
        guard bytes.count == size else { throw Failure.fixtureIdentity }
        return bytes
    }

    static func existingSpeech(_ root: URL) throws -> [Speech] {
        let records = [
            ("conversion-source.wav", 108032,
                "8741b5ebb943f4c39006b6c7a7dd5ca92f344edb402744ad7132ee1f94ff45b4",
                "I found a strange device near the portal."),
            ("conversion-reference.wav", 123392,
                "0840a3b08d2d438804e760afa54bc1c9cdf1c8b33bffdc1ab458be4ab3740cd2",
                "Please close the window and bring the notebook."),
        ]
        return try records.map { name, count, expectedDigest, words in
            let url = root.appendingPathComponent(name)
            let digest = hex(try readBounded(url, max: fixtureCap, exact: count))
            guard digest == expectedDigest else { throw Failure.fixtureIdentity }
            return Speech(id: name, mode: "baseline", digest: digest, expected: words, url: url, maximumWER: 0.1)
        }
    }

    static func fixedHumanSpeech(_ root: URL, sources: URL) throws -> (speech: [Speech], rawDigest: String) {
        let decoder = JSONDecoder()
        let rawSources = try readBounded(sources, max: 32_768)
        guard hex(rawSources) == expectedSourcesHash else { throw Failure.fixtureIdentity }
        let pins = try decoder.decode([HumanSource].self, from: rawSources)
        let rawManifest = try readBounded(root.appendingPathComponent("manifest.json"), max: 65_536)
        let manifest = try decoder.decode(HumanManifest.self, from: rawManifest)
        guard manifest.schemaVersion == 1,
              pins.map(\.offset) == [100, 300, 1200, 1700], Set(pins.map(\.speaker_id)).count == 4,
              manifest.cases.count == 8, Set(manifest.cases.map(\.id)).count == 8
        else { throw Failure.fixtureIdentity }
        let byFile = Dictionary(grouping: manifest.cases, by: \.file)
        guard byFile.count == 4 else { throw Failure.fixtureIdentity }
        var speech: [Speech] = []
        for pin in pins {
            let name = pin.id + "-original.wav"
            guard pin.license == "CC-BY-4.0",
                  pin.datasetRevision == "71cacbfb7e2354c4226d01e70d77d5fca3d04ba1",
                  let entries = byFile[name], entries.count == 2,
                  Set(entries.map(\.mode)) == ["baseline", "reference"],
                  Set(entries.map(\.sha256)).count == 1, Set(entries.map(\.bytes)).count == 1
            else { throw Failure.fixtureIdentity }
            let original = root.appendingPathComponent(pin.id + ".flac")
            guard hex(try readBounded(original, max: fixtureCap, exact: pin.sourceBytes)) == pin.sourceSHA256
            else { throw Failure.fixtureIdentity }
            let url = root.appendingPathComponent(name)
            let digest = hex(try readBounded(url, max: fixtureCap, exact: entries[0].bytes))
            let audio = try AVAudioFile(forReading: url)
            guard audio.processingFormat.channelCount == 1, audio.processingFormat.sampleRate == 24_000,
                  audio.length == AVAudioFramePosition(pin.sourceFrames * 3 / 2)
            else { throw Failure.fixtureIdentity }
            for entry in entries {
                guard entry.id == pin.id + "-" + entry.mode, entry.expected == pin.referenceText,
                      digest == entry.sha256, digest == entry.sourceSHA256, entry.corpusFLACSHA256 == pin.sourceSHA256
                else { throw Failure.fixtureIdentity }
                speech.append(Speech(
                    id: entry.id, mode: entry.mode, digest: digest, expected: pin.referenceText,
                    url: url, maximumWER: 0))
            }
        }
        return (speech, hex(rawManifest))
    }

    @MainActor static func recognize(_ url: URL, mode: String, recognizer: OnDeviceTranscription,
                                    activity: @escaping @MainActor () -> Void) async throws -> String {
        if mode == "reference" {
            return try await recognizer.transcribeReference(url, activity: activity)
        }
        return try await recognizer.transcribe(url, activity: activity)
    }

    @MainActor static func speechCheck(_ clip: Speech, recognizer: OnDeviceTranscription) async -> Result {
        let started = Date()
        var activity = 0
        do {
            let recognized = try await recognize(clip.url, mode: clip.mode, recognizer: recognizer) { activity += 1 }
            let evidence = recognizer.lastEvidence
            let wer = LocalStudioEvidence.wordErrorRate(expected: clip.expected, actual: recognized)
            let expectedContext: Double? = clip.mode == "reference" ? 0.25 : nil
            let ok = wer <= clip.maximumWER && activity == 1
                && evidence?.inputSHA256 == clip.digest
                && evidence?.transcriptSHA256 == hex(Data(recognized.utf8))
                && evidence?.modelRevision == modelRevision
                && evidence?.referenceLeadingSeconds == expectedContext
                && (evidence?.tokenCount ?? 0) > 0
                && evidence?.meanTokenConfidence.isFinite == true
            return Result(id: clip.id, mode: clip.mode, inputSHA256: clip.digest, expected: clip.expected,
                          recognized: recognized, error: ok ? nil : "Speech threshold or production receipt failed",
                          wordErrorRate: wer, tokenEvidence: evidence, successActivityCount: activity,
                          elapsedSeconds: Date().timeIntervalSince(started), accepted: ok)
        } catch {
            return Result(id: clip.id, mode: clip.mode, inputSHA256: clip.digest, expected: clip.expected,
                          recognized: nil, error: String(describing: error), wordErrorRate: nil,
                          tokenEvidence: recognizer.lastEvidence, successActivityCount: activity,
                          elapsedSeconds: Date().timeIntervalSince(started), accepted: false)
        }
    }

    @MainActor static func silenceCheck(
        _ url: URL, mode: String, digest: String, recognizer: OnDeviceTranscription
    ) async -> Result {
        let start = Date()
        var activity = 0
        var text: String?, rejection: String?
        var correctFailure = false
        do {
            text = try await recognize(url, mode: mode, recognizer: recognizer) { activity += 1 }
            rejection = "Silence unexpectedly recognized"
        } catch OnDeviceTranscription.Failure.noSpeech {
            correctFailure = true
            rejection = "noSpeech"
        } catch {
            rejection = String(describing: error)
        }
        let evidence = recognizer.lastEvidence
        return Result(id: "silence-" + mode, mode: mode, inputSHA256: digest, expected: nil, recognized: text,
                      error: rejection, wordErrorRate: nil, tokenEvidence: evidence, successActivityCount: activity,
                      elapsedSeconds: Date().timeIntervalSince(start),
                      accepted: correctFailure && evidence == nil && activity == 0)
    }

    @MainActor static func main() async throws {
        guard CommandLine.arguments.count == 6 else { throw Failure.arguments }
        let localFixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let humanFixtures = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let models = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[4])
        let sourceCommit = CommandLine.arguments[5]
        guard sourceCommit.range(of: "^[a-f0-9]{40}$", options: .regularExpression) != nil,
              BundledASRAssets.revision == modelRevision
        else { throw Failure.arguments }

        let originals = try existingSpeech(localFixtures)
        let human = try fixedHumanSpeech(humanFixtures, sources: localFixtures.appendingPathComponent("holdout-sources.json"))
        let silence = localFixtures.appendingPathComponent("silence.wav")
        let silenceDigest = hex(try readBounded(silence, max: fixtureCap, exact: 32044))
        guard silenceDigest == "643f8a8dc8bd9c19225afffad2becfec5426180b3749cb208abdf1a6c8354efc"
        else { throw Failure.fixtureIdentity }

        var results: [Result] = []
        var cancelledWasRejected = false
        var retryAfterCancellationPassed = false
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        func persist(status: String, first: Bool = false) throws {
            let report = Report(status: status, sourceCommit: sourceCommit, humanInputManifestSHA256: human.rawDigest,
                                cancelledRequestRejected: cancelledWasRejected,
                                retryAfterCancellationPassed: retryAfterCancellationPassed, results: results)
            try encoder.encode(report).write(to: output, options: first ? .withoutOverwriting : .atomic)
        }
        try persist(status: "INCOMPLETE", first: true)
        let recognizer = OnDeviceTranscription(bundle: models)
        do {
            try await recognizer.authorize()
            var cancellationActivity = 0
            let cancelled = Task {
                try await recognizer.transcribe(originals[0].url) { cancellationActivity += 1 }
            }
            try await Task.sleep(for: .milliseconds(20))
            cancelled.cancel()
            do {
                _ = try await cancelled.value
            } catch is CancellationError {
                cancelledWasRejected = recognizer.lastEvidence == nil && cancellationActivity == 0
            }

            for (index, clip) in (originals + human.speech).enumerated() {
                let result = await speechCheck(clip, recognizer: recognizer)
                results.append(result)
                if index == 0 { retryAfterCancellationPassed = result.accepted }
                try persist(status: "INCOMPLETE")
            }
            for mode in ["baseline", "reference"] {
                results.append(await silenceCheck(silence, mode: mode, digest: silenceDigest, recognizer: recognizer))
                try persist(status: "INCOMPLETE")
            }
            guard results.count == 12, results.allSatisfy(\.accepted),
                  cancelledWasRejected, retryAfterCancellationPassed
            else { throw Failure.acceptance }
            try persist(status: "NARROW_PRODUCTION_ASR_FIXTURES_PASSED_NO_DEVICE_CLAIM")
            print("2 prior speech, 8 human route, 2 silence cases and cancellation/retry passed; not device/general ASR evidence")
        } catch {
            try persist(status: "FAILED")
            throw error
        }
    }
}
