@preconcurrency import CoreML
import Darwin
import FluidAudio
import Foundation

/// Read-only diagnostics for licensed control fixtures, not a quality or identity gate.
@main struct Probe {
    struct Manifest: Decodable { let cases: [InputCase] }
    struct InputCase: Decodable { let name: String; let seconds: Double; let audioSHA256: String }

    struct Segment: Codable, Equatable {
        let speaker: String
        let start: Double
        let end: Double
    }

    struct MaskEvidence: Encodable {
        let numChunks: Int
        let numFrames: Int
        let numSpeakers: Int
        let chunkOffsets: [Double]
        let frameDuration: Double
        let speakerWeights: [[[Float]]]

        init(_ evidence: SegmentationOutput) throws {
            try Probe.require((1...32).contains(evidence.numChunks) && (1...2000).contains(evidence.numFrames)
                && (1...8).contains(evidence.numSpeakers) && evidence.chunkOffsets.count == evidence.numChunks
                && evidence.chunkOffsets.allSatisfy { $0.isFinite && $0 >= 0 }
                && evidence.frameDuration.isFinite && evidence.frameDuration > 0
                && evidence.speakerWeights.count == evidence.numChunks
                && evidence.speakerWeights.allSatisfy { chunk in
                    chunk.count == evidence.numFrames && chunk.allSatisfy { row in
                        row.count == evidence.numSpeakers && row.allSatisfy { $0.isFinite && (0...1).contains($0) }
                    }
                }, "invalid segmentation shape or weights")
            numChunks = evidence.numChunks
            numFrames = evidence.numFrames
            numSpeakers = evidence.numSpeakers
            chunkOffsets = evidence.chunkOffsets
            frameDuration = evidence.frameDuration
            speakerWeights = evidence.speakerWeights
        }
    }

    // Decode only assignment metadata. No embedding256 or rho128 in evidence or logs.
    struct Assignment: Codable {
        let chunkIndex: Int
        let speakerIndex: Int
        let startFrame: Int
        let endFrame: Int
        let startTime: Double
        let endTime: Double
        let cluster: Int
    }

    struct PairDistance: Codable {
        let first: Int
        let second: Int
        let distance: Double
    }
    struct StageStatistics: Codable {
        let embeddingCount: Int
        let finite256DCount: Int
        let embeddingNorms: [Double?]
        let pairwiseUnitEuclidean: [PairDistance]
        let ahcTrainingIndices: [Int]
        let ahcInitialPartition: [Int]
        let vbxNumClusters: Int
        let vbxPiMasses: [Double?]
        let centroidCount: Int
    }
    struct StageExport: Decodable {
        let schemaVersion: Int
        let assignments: [Assignment]
        let stages: StageStatistics
    }

    struct CaseEvidence: Encodable {
        let name: String
        let requestedSeconds: Double
        let audioSHA256: String
        var clipSHA256: String?
        var clipReceiptSHA256: String?
        var canonicalFrames: Int?
        var decodedFrames: Int?
        var modelRevision: String?
        var policyVersion: Int?
        var productionOverlap: LocalOverlapPolicy.Evidence?
        var productionOutcome = "not-run"
        var diagnosticOutcome = "not-run"
        var productionParity = "not-compared"
        var segmentation: MaskEvidence?
        var embeddingCount: Int?
        var assignments: [Assignment] = []
        var stageStatistics: StageStatistics?
        var diagnosticSegments: [Segment] = []
        var productionSegments: [Segment] = []
        var preservedInputs = false
        var failures: [String] = []
    }

    struct CaseStatus: Encodable {
        let name: String
        let artifact: String
        let productionParity: String
        let failures: [String]
    }

    struct Summary: Encodable {
        let scope = "Licensed speech controls; anonymous model evidence only, not identity or acceptance."
        let fixtureManifestSHA256: String
        let pinnedModelLockSHA256: String
        let cases: [CaseStatus]
    }

    enum Failure: Error { case failed(String) }

    static func require(_ condition: Bool, _ reason: String) throws {
        guard condition else { throw Failure.failed(reason) }
    }

    static func log(_ message: String) {
        print(message)
        fflush(stdout)
    }

    static func digest(_ path: URL) throws -> String {
        try SeparationStore.digest(path, maximum: 4_000_000)
    }

    static func save<T: Encodable>(_ evidence: T, to path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(evidence).write(to: path, options: .withoutOverwriting)
    }

    // The same pinned model names, PLDA decoding and compute selection as the adapter.
    static func loadModels(_ bundle: URL) throws -> OfflineDiarizerModels {
        try LocalSpeakerDiarization.verify(bundle)
        let start = Date()
        func model(_ name: String, cpuOnly: Bool = false) throws -> MLModel {
            try Task.checkCancellation()
            let config = MLModelConfiguration()
            config.computeUnits = cpuOnly ? .cpuOnly : .all
            return try MLModel(contentsOf: bundle.appendingPathComponent(name + ".mlmodelc"), configuration: config)
        }
        let psiData = try Data(contentsOf: bundle.appendingPathComponent("plda-parameters.json"))
        guard let object = try JSONSerialization.jsonObject(with: psiData) as? [String: Any],
              let tensors = object["tensors"] as? [String: Any], let psi = tensors["psi"] as? [String: Any],
              let base64 = psi["data_base64"] as? String, let bytes = Data(base64Encoded: base64),
              bytes.count == 128 * 4 else { throw LocalSpeakerDiarization.Failure.invalidBundle }
        let values: [Double] = bytes.withUnsafeBytes { raw in
            (0..<128).map { Double(Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self)))) }
        }
        try require(values.allSatisfy { $0.isFinite && $0 >= 0 }, "invalid PLDA parameters")
        return try OfflineDiarizerModels(
            segmentationModel: model("Segmentation"), fbankModel: model("FBank", cpuOnly: true),
            embeddingModel: model("Embedding"), pldaRhoModel: model("PldaRho"), pldaPsi: values,
            compilationDuration: Date().timeIntervalSince(start)
        )
    }

    static func runCase(_ item: InputCase, fixtures: URL, modelBundle: URL, models: OfflineDiarizerModels,
                        work: URL) async -> CaseEvidence {
        var evidence = CaseEvidence(name: item.name, requestedSeconds: item.seconds, audioSHA256: item.audioSHA256)
        let sourceURL = fixtures.appendingPathComponent(item.name + ".wav")
        var originals = [(sourceURL, item.audioSHA256)]
        do {
            try require(try digest(sourceURL) == item.audioSHA256, "fixture source SHA mismatch")
            let store = SeparationStore(root: work.appendingPathComponent(item.name, isDirectory: true))
            let reviews = ClipSpeakerReviewStore(clipStore: store)
            let source = SeparationClipHandoff.Source(jobID: UUID(), url: sourceURL, sha256: item.audioSHA256)
            let clip = try await SeparationClipHandoff.prepare(source: source, start: 0, seconds: item.seconds, store: store)
            let receipt = clip.url.deletingLastPathComponent().appendingPathComponent("receipt.json")
            originals.append((clip.url, clip.sha256))
            originals.append((receipt, clip.receiptSHA256))
            evidence.canonicalFrames = clip.frames
            evidence.clipSHA256 = clip.sha256
            evidence.clipReceiptSHA256 = clip.receiptSHA256
            if item.seconds < 3 {
                // Exercise the same production admission gate; don't run either model for this case.
                do {
                    _ = try await ClipSpeakerReviewAnalyzer.analyze(clip, store: reviews, bundle: modelBundle)
                    throw Failure.failed("below-minimum retained clip was admitted")
                } catch ClipSpeakerReviewStore.Failure.unsupported {
                    evidence.productionOutcome = "unsupported"
                    evidence.diagnosticOutcome = "not-run-unsupported"
                    evidence.productionParity = "below-minimum-rejected"
                }
            } else {
                let snapshot = try reviews.snapshot(for: clip)
                defer { try? FileManager.default.removeItem(at: snapshot) }
                let samples = try LocalSpeakerDiarization.decodeRetainedClip(snapshot, frames: clip.frames, sourceSHA256: clip.sha256)
                evidence.decodedFrames = samples.count

                // Compare the instrumented pass to the production adapter on the same verified canonical bytes.
                do {
                    let production = try await LocalSpeakerDiarization.analyze(
                        source: snapshot, bundle: modelBundle, retainedClipFrames: clip.frames,
                        progress: { log("production \(item.name): \($0)") }
                    )
                    try reviews.validate(production, for: clip)
                    evidence.productionOutcome = "segments"
                    evidence.productionSegments = production.segments.map { Segment(speaker: $0.speaker, start: $0.start, end: $0.end) }
                    evidence.modelRevision = production.modelRevision
                    evidence.policyVersion = production.selectionPolicyVersion
                    evidence.productionOverlap = production.rawOverlap
                } catch OfflineDiarizationError.noSpeechDetected {
                    evidence.productionOutcome = "no-speech"
                } catch {
                    evidence.productionOutcome = "error"
                    evidence.failures.append("production: \(error)")
                }

                let rawExport = work.appendingPathComponent(".assignment-export-" + UUID().uuidString + ".json")
                defer { try? FileManager.default.removeItem(at: rawExport) }
                // Mirror all production settings. The only extra setting is the vendor's read-only diagnostic export.
                var config = OfflineDiarizerConfig()
                config.segmentation.batchSize = 1
                config.embedding.batchSize = 1
                config.embedding.excludeOverlap = true
                config.postProcessing.exclusiveSegments = false
                config.exposeChunkEmbeddings = false
                config.export.embeddingsPath = rawExport.path
                let manager = OfflineDiarizerManager(config: config)
                manager.initialize(models: models)
                do {
                    let prepared = try await manager.prepare(audio: samples) { done, total in
                        log("diagnostic \(item.name): chunks \(done)/\(total)")
                    }
                    evidence.segmentation = try MaskEvidence(prepared.segmentationEvidence)
                    evidence.embeddingCount = prepared.embeddingCount
                    try require((0...512).contains(prepared.embeddingCount), "embedding count out of control bounds")
                    let diagnostic = try manager.cluster(prepared)
                    evidence.diagnosticSegments = diagnostic.segments.map {
                        Segment(speaker: $0.speakerId, start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds))
                    }
                    var export = Data()
                    try RetainedMediaReader.read(rawExport, maximumBytes: 262_144) { export.append($0) }
                    let staged = try JSONDecoder().decode(StageExport.self, from: export)
                    try require(staged.schemaVersion == 1 && staged.stages.embeddingCount == prepared.embeddingCount,
                                "stage export version/count mismatch")
                    evidence.assignments = staged.assignments
                    evidence.stageStatistics = staged.stages
                    try require(evidence.assignments.count == prepared.embeddingCount, "assignment count does not match embeddings")
                    evidence.diagnosticOutcome = "segments"
                } catch OfflineDiarizationError.noSpeechDetected {
                    evidence.diagnosticOutcome = "no-speech"
                    if evidence.segmentation == nil || evidence.embeddingCount != 0 {
                        evidence.failures.append("no-speech outcome lacked a zero-embedding prepared mask")
                    }
                } catch {
                    evidence.diagnosticOutcome = "error"
                    evidence.failures.append("diagnostic: \(error)")
                }

                if evidence.productionOutcome == "segments" && evidence.diagnosticOutcome == "segments"
                    && evidence.productionSegments == evidence.diagnosticSegments {
                    evidence.productionParity = "exact-segments"
                } else if evidence.productionOutcome == "no-speech" && evidence.diagnosticOutcome == "no-speech" {
                    evidence.productionParity = "both-no-speech"
                } else {
                    evidence.productionParity = "mismatch"
                    evidence.failures.append("instrumented outcome/segments do not exactly match production")
                }
                try require(try digest(snapshot) == clip.sha256, "canonical analysis snapshot changed")
                try reviews.verify(clip)
            }
        } catch {
            evidence.failures.append("retained input/analysis: \(error)")
        }

        var preserved = true
        for (path, expected) in originals {
            do { try require(try digest(path) == expected, "mismatched digest") }
            catch {
                preserved = false
                evidence.failures.append("preservation of \(path.lastPathComponent): \(error)")
            }
        }
        evidence.preservedInputs = preserved
        return evidence
    }

    static func main() async throws {
        try require(CommandLine.arguments.count == 4, "usage: Probe MODELS FIXTURES OUTPUT")
        let modelBundle = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        let manifestURL = fixtures.appendingPathComponent("fixture.json")
        var manifestData = Data()
        try RetainedMediaReader.read(manifestURL, maximumBytes: 262_144) { manifestData.append($0) }
        let manifest = try JSONDecoder().decode(Manifest.self, from: manifestData)
        try require((1...32).contains(manifest.cases.count)
            && Set(manifest.cases.map(\.name)).count == manifest.cases.count
            && manifest.cases.allSatisfy {
                $0.name.range(of: "^[a-z0-9][a-z0-9-]{0,62}$", options: .regularExpression) != nil
                    && $0.audioSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
                    && (0.5...10).contains($0.seconds)
            }, "invalid control manifest")
        try require(!FileManager.default.fileExists(atPath: output.path), "refusing existing output")
        let models = try loadModels(modelBundle)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let work = output.appendingPathComponent(".work-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }
        var results: [CaseStatus] = []
        for item in manifest.cases {
            var evidence = await runCase(item, fixtures: fixtures, modelBundle: modelBundle, models: models, work: work)
            let artifact = item.name + "-control.json"
            do { try save(evidence, to: output.appendingPathComponent(artifact)) }
            catch { evidence.failures.append("writing evidence: \(error)") }
            results.append(CaseStatus(name: item.name, artifact: artifact, productionParity: evidence.productionParity, failures: evidence.failures))
            log("\(evidence.failures.isEmpty ? "PASS" : "FAIL") \(item.name): \(evidence.productionParity), embeddings=\(evidence.embeddingCount.map(String.init) ?? "n/a")")
            for failure in evidence.failures { log("  \(failure)") }
        }
        let summary = Summary(fixtureManifestSHA256: try digest(manifestURL),
                              pinnedModelLockSHA256: try digest(modelBundle.appendingPathComponent("resource-lock.json")),
                              cases: results)
        try save(summary, to: output.appendingPathComponent("summary.json"))
        let failures = results.filter { !$0.failures.isEmpty }.map(\.name)
        try require(failures.isEmpty, "controls with parity or execution failures: " + failures.joined(separator: ", "))
    }
}
