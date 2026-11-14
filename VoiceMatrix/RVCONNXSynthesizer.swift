#if os(iOS)
import Foundation
import CryptoKit
import OnnxRuntimeBindings

/// CPU-only diagnostic synthesizer. No UI route is enabled until the upstream
/// feature/pitch/retrieval pipeline and physical-device validation are available.
actor RVCONNXSynthesizer {
    private var environment: ORTEnv?
    private var session: ORTSession?
    private var snapshot: URL?

    init(assetRoot: URL, cacheDirectory: URL) throws {
        var digest = SHA256()
        let model = try RVCSynthesisAssets.snapshot(root: assetRoot, cache: cacheDirectory,
            update: { digest.update(data: $0) },
            finish: { digest.finalize().map { String(format: "%02x", $0) }.joined() })
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            try options.setGraphOptimizationLevel(.all)
            // No CoreML/XNNPACK provider: the verified phase sum uses float64.
            let loaded = try ORTSession(env: env, modelPath: model.path, sessionOptions: options)
            let names: Set<String> = ["phone","lengths","pitch","pitchf","speaker","latent_noise","phase_noise","excitation_noise"]
            guard Set(try loaded.inputNames()) == names, try loaded.outputNames() == ["audio"] else {
                throw RVCSynthesisFailure.incompatibleModel
            }
            environment = env
            session = loaded
            snapshot = model
        } catch {
            try? FileManager.default.removeItem(at: model.deletingLastPathComponent())
            throw error
        }
    }

    func run(_ input: RVCSynthesisInputs) throws -> [Float] {
        try Task.checkCancellation()
        guard let session else { throw RVCSynthesisFailure.unavailable }
        let encoded = try input.tensors()
        var backing: [String: NSMutableData] = [:]
        var values: [String: ORTValue] = [:]
        for (name, tensor) in encoded {
            let data = NSMutableData(data: tensor.bytes)
            backing[name] = data
            values[name] = try ORTValue(tensorData: data,
                elementType: tensor.kind == .float32 ? .float : .int64,
                shape: tensor.shape.map { NSNumber(value: $0) })
        }
        let result = try withExtendedLifetime(backing) {
            try session.run(withInputs: values, outputNames: ["audio"], runOptions: nil)
        }
        try Task.checkCancellation()
        guard let audio = result["audio"] else { throw RVCSynthesisFailure.invalidOutput }
        let info = try audio.tensorTypeAndShapeInfo()
        let data = try audio.tensorData()
        guard info.elementType == .float, info.shape.map({ $0.intValue }) == [1,1,368800],
              data.length == 368800 * MemoryLayout<Float>.size else { throw RVCSynthesisFailure.invalidOutput }
        let copied = Array(UnsafeBufferPointer(start: data.bytes.assumingMemoryBound(to: Float.self), count: 368800))
        guard copied.allSatisfy({ $0.isFinite }) else { throw RVCSynthesisFailure.invalidOutput }
        return copied
    }

    func close() {
        session = nil
        environment = nil
        if let snapshot { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
        snapshot = nil
    }
    deinit {
        if let snapshot { try? FileManager.default.removeItem(at: snapshot.deletingLastPathComponent()) }
    }
}
#endif
