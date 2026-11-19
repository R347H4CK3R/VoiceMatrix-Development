import Foundation
import AVFoundation
import CryptoKit
@preconcurrency import CoreML
import FluidAudio

/// Bundled ASR only. No OS speech permission/assets, service, downloader or purge.
/// Each call owns and releases its models before returning, including on cancellation.
@MainActor final class OnDeviceTranscription {
    enum Failure: LocalizedError {
        case unavailable, busy, noSpeech, timeout, invalidAudio
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Bundled speech recognition could not finish. Source and existing voices were retained; no server fallback was used."
            case .busy: return "A local transcription is already running."
            case .noSpeech: return "No usable speech transcript was found in this window."
            case .timeout: return "Speech recognition exceeded 45 seconds and was stopped at a safe model boundary. Retained media was kept."
            case .invalidAudio: return "Local transcription requires a mono WAV of 0.2–30 seconds, at 16–48 kHz, no larger than 8 MiB."
            }
        }
    }
    struct Evidence: Codable, Sendable {
        let schemaVersion = 2
        let modelRevision = BundledASRAssets.revision
        let inputSHA256, transcriptSHA256: String
        let recoveryTailSeconds: Double?
        let referenceLeadingSeconds: Double?
        let tokenCount: Int
        let meanTokenConfidence: Float
        let confidenceMeaning = "Uncalibrated mean token softmax, not transcript accuracy"
    }
    private(set) var lastEvidence: Evidence?
    private let bundle: URL?
    private var token: UUID?
    private var deadlineExpired = false
    init(bundle: URL? = Bundle.main.url(forResource: "ParakeetASR", withExtension: nil)) { self.bundle = bundle }

    /// Preserve the caller interface, but do not ask for OS speech authorization.
    /// This verifies the small pinned manifest, without loading model weights.
    func authorize() async throws {
        try Task.checkCancellation()
        guard let bundle else { throw BundledASRAssets.Failure.missing }
        do { _ = try BundledASRAssets.manifest(at: bundle) }
        catch is CancellationError { throw CancellationError() }
        catch { throw BundledASRAssets.Failure.invalid }
    }
    func transcribe(_ file: URL, activity: @escaping @MainActor () -> Void = {}) async throws -> String {
        try await transcribe(file, referenceContext: false, activity: activity)
    }
    /// Reference conditioning recognition only. Generated-output verification stays unchanged.
    func transcribeReference(_ file: URL, activity: @escaping @MainActor () -> Void = {}) async throws -> String {
        try await transcribe(file, referenceContext: true, activity: activity)
    }
    private func transcribe(_ file: URL, referenceContext: Bool, activity: @escaping @MainActor () -> Void) async throws -> String {
        try Task.checkCancellation()
        guard token == nil else { throw Failure.busy }
        guard let bundle else { throw BundledASRAssets.Failure.missing }
        let run = UUID(); token = run; deadlineExpired = false; lastEvidence = nil
        let worker = Task.detached(priority: .userInitiated) { try await Self.recognize(file, bundle: bundle, referenceContext: referenceContext) }
        let deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.token == run else { return }
            self.deadlineExpired = true; worker.cancel()
        }
        defer { deadline.cancel(); token = nil }
        do {
            let (text, evidence) = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            if deadlineExpired { throw Failure.timeout }
            lastEvidence = evidence
            activity() // A real final result, never a timer-based progress claim.
            return text
        } catch {
            if Task.isCancelled { throw CancellationError() }
            if deadlineExpired { throw Failure.timeout }
            if error is Failure || error is BundledASRAssets.Failure { throw error }
            throw Failure.unavailable
        }
    }
    private nonisolated static func recognize(_ file: URL, bundle: URL, referenceContext: Bool) async throws -> (String, Evidence) {
        try Task.checkCancellation()
        guard file.isFileURL, file.pathExtension.lowercased() == "wav" else { throw Failure.invalidAudio }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, (44...8_388_608).contains(size) else { throw Failure.invalidAudio }
        let audio = try AVAudioFile(forReading: file)
        let rate = audio.processingFormat.sampleRate
        let seconds = Double(audio.length) / rate
        guard rate.isFinite, (16_000...48_000).contains(rate), audio.processingFormat.channelCount == 1,
              seconds.isFinite, (0.2...30).contains(seconds) else { throw Failure.invalidAudio }
        var referenceLeadingSeconds: Double?
        if referenceContext {
            guard let leadingFrames = BundledASRPolicy.referenceLeadingFrameCount(frames: Int(audio.length), sampleRate: rate) else { throw Failure.invalidAudio }
            referenceLeadingSeconds = Double(leadingFrames) / rate
        }
        let inputSHA256 = try inputDigest(file, byteCount: size)
        try BundledASRAssets.verify(bundle)
        try Task.checkCancellation()
        let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
        // Explicitly select the larger rebuilt encoder. Pinned SDK documents
        // right-context token corruption in the original 6-bit Encoder.mlmodelc.
        let manager = AsrManager(config: ASRConfig(parallelChunkConcurrency: 1), models:
            try AsrModels.loadLocal(from: bundle, version: .v3, configuration: config,
                                    encoderPrecision: .int8V2, encoderComputeUnits: .cpuAndNeuralEngine,
                                    localFrontend: .originalNemo231))
        do {
            try Task.checkCancellation()
            var decoder = try TdtDecoderState(decoderLayers: 2)
            var result: ASRResult
            if referenceContext {
                result = try await manager.transcribe(try referenceLeadingBuffer(file), decoderState: &decoder)
            } else {
                result = try await manager.transcribe(file, decoderState: &decoder)
            }
            try Task.checkCancellation()
            var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var recoveryTailSeconds: Double?
            if !referenceContext && !LocalStudioEvidence.usableTranscript(text) {
                _ = try inputDigest(file, byteCount: size, matching: inputSHA256)
                if let (buffer, tail) = try recoveryBuffer(file, text:text) {
                    try Task.checkCancellation()
                    var retryDecoder=try TdtDecoderState(decoderLayers:2)
                    let retry=try await manager.transcribe(buffer,decoderState:&retryDecoder)
                    try Task.checkCancellation()
                    let retryText=retry.text.trimmingCharacters(in:.whitespacesAndNewlines)
                    if LocalStudioEvidence.usableTranscript(retryText), let timings=retry.tokenTimings,
                       BundledASRPolicy.admittedRecoveryTokenMean(timings.map(\.confidence)) != nil {
                        result=retry;text=retryText;recoveryTailSeconds=tail
                    }
                }
            }
            // Do not use result.confidence: pinned SDK substitutes 0.5 if scores
            // are absent. tokenTimings exists only when actual per-token scores match.
            guard LocalStudioEvidence.usableTranscript(text), let timings = result.tokenTimings,
                  let mean = BundledASRPolicy.admittedTokenMean(timings.map(\.confidence)) else { throw Failure.noSpeech }
            // FluidAudio reopens the pathname. Reject changes before publishing
            // evidence, rather than attaching the earlier hash to different audio.
            _ = try inputDigest(file, byteCount: size, matching: inputSHA256)
            let evidence = Evidence(inputSHA256: inputSHA256,
                transcriptSHA256: SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined(),
                recoveryTailSeconds: recoveryTailSeconds, referenceLeadingSeconds: referenceLeadingSeconds, tokenCount: timings.count, meanTokenConfidence: mean)
            await manager.cleanup()
            return (text, evidence)
        } catch {
            await manager.cleanup()
            throw error
        }
    }
    /// Bounded in-memory context. No temporary WAV, source mutation, prompt or retry padding.
    nonisolated static func referenceLeadingBuffer(_ file: URL) throws -> AVAudioPCMBuffer {
        try Task.checkCancellation()
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard file.isFileURL, file.pathExtension.lowercased() == "wav", values.isRegularFile == true,
              values.isSymbolicLink != true, let size = values.fileSize, (44...8_388_608).contains(size) else { throw Failure.invalidAudio }
        let audio = try AVAudioFile(forReading: file)
        let rate = audio.processingFormat.sampleRate
        guard audio.processingFormat.channelCount == 1, audio.length > 0, audio.length <= 1_440_000,
              let lead = BundledASRPolicy.referenceLeadingFrameCount(frames: Int(audio.length), sampleRate: rate) else { throw Failure.invalidAudio }
        let original = try readReferenceFrames(format: audio.processingFormat, frameCount: AVAudioFrameCount(audio.length)) { chunk, requested in
            try audio.read(into: chunk, frameCount: requested)
        }
        guard let input = original.floatChannelData?[0] else { throw Failure.invalidAudio }
        let total = original.frameLength + AVAudioFrameCount(lead)
        guard let padded = AVAudioPCMBuffer(pcmFormat: original.format, frameCapacity: total), let output = padded.floatChannelData?[0] else { throw Failure.invalidAudio }
        padded.frameLength = total
        output.initialize(repeating: 0, count: lead)
        output.advanced(by: lead).update(from: input, count: Int(original.frameLength))
        try Task.checkCancellation()
        return padded
    }

    /// AVAudioFile may return a short read before EOF. Accept only a complete,
    /// bounded PCM sequence; zero progress, early EOF and cancellation fail closed.
    nonisolated static func readReferenceFrames(format: AVAudioFormat, frameCount: AVAudioFrameCount,
                                                read: (AVAudioPCMBuffer, AVAudioFrameCount) throws -> Void) throws -> AVAudioPCMBuffer {
        try Task.checkCancellation()
        guard format.channelCount == 1, format.commonFormat == .pcmFormatFloat32,
              (1...1_440_000).contains(frameCount),
              let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: min(4096, frameCount)),
              let output = result.floatChannelData?[0] else { throw Failure.invalidAudio }
        var completed: AVAudioFrameCount = 0
        while completed < frameCount {
            try Task.checkCancellation()
            let requested = min(4096, frameCount - completed)
            chunk.frameLength = 0
            try read(chunk, requested)
            try Task.checkCancellation()
            guard chunk.frameLength > 0, chunk.frameLength <= requested,
                  let input = chunk.floatChannelData?[0] else { throw Failure.invalidAudio }
            output.advanced(by: Int(completed)).update(from: input, count: Int(chunk.frameLength))
            completed += chunk.frameLength
        }
        guard completed == frameCount else { throw Failure.invalidAudio }
        result.frameLength = completed
        try Task.checkCancellation()
        return result
    }

    private nonisolated static func recoveryBuffer(_ file:URL,text:String) throws -> (AVAudioPCMBuffer,Double)? {
        try Task.checkCancellation()
        let audio=try AVAudioFile(forReading:file)
        let rate=audio.processingFormat.sampleRate
        guard rate.isFinite,(16000...48000).contains(rate),audio.processingFormat.channelCount==1,
              audio.length>0,audio.length<=1440000,Double(audio.length)/rate<=30,
              let original=AVAudioPCMBuffer(pcmFormat:audio.processingFormat,frameCapacity:AVAudioFrameCount(audio.length)) else { throw Failure.invalidAudio }
        try audio.read(into:original)
        guard original.frameLength==AVAudioFrameCount(audio.length),let input=original.floatChannelData?[0] else { throw Failure.invalidAudio }
        let samples=Array(UnsafeBufferPointer(start:input,count:Int(original.frameLength)))
        guard let tail=BundledASRPolicy.recoveryTailFrameCount(text:text,samples:samples,sampleRate:rate) else { return nil }
        let total=original.frameLength+AVAudioFrameCount(tail)
        guard let padded=AVAudioPCMBuffer(pcmFormat:original.format,frameCapacity:total),let output=padded.floatChannelData?[0] else { throw Failure.invalidAudio }
        padded.frameLength=total
        samples.withUnsafeBufferPointer { source in
            if let base=source.baseAddress { output.update(from:base,count:samples.count) }
        }
        output.advanced(by:samples.count).initialize(repeating:0,count:tail)
        try Task.checkCancellation()
        return (padded,Double(tail)/rate)
    }
    nonisolated static func inputDigest(_ file: URL, byteCount: Int, matching: String? = nil) throws -> String {
        try Task.checkCancellation()
        guard file.isFileURL, (1...8_388_608).contains(byteCount) else { throw Failure.invalidAudio }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.fileSize == byteCount else { throw Failure.invalidAudio }
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        var hash = SHA256(), count = 0
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation(); count += bytes.count
            guard count <= byteCount else { throw Failure.invalidAudio }
            hash.update(data: bytes)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard count == byteCount, matching == nil || matching == digest else { throw Failure.invalidAudio }
        return digest
    }

}
