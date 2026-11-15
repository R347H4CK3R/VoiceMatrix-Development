#if os(iOS)
import Foundation
import CryptoKit
import OnnxRuntimeBindings

actor RVCONNXHuBERT {
    private var environment: ORTEnv?
    private var session: ORTSession?
    private var snapshot: URL?
    init(assetRoot: URL, cacheDirectory: URL) throws {
        var digest=SHA256()
        let model=try RVCSynthesisAssets.snapshot(root:assetRoot,cache:cacheDirectory,profile:"hubert-147680-cpu",
            update:{digest.update(data:$0)},finish:{digest.finalize().map{String(format:"%02x",$0)}.joined()})
        do {
            let env=try ORTEnv(loggingLevel:.warning)
            let options=try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            try options.setGraphOptimizationLevel(.all)
            let loaded=try ORTSession(env:env,modelPath:model.path,sessionOptions:options)
            guard try loaded.inputNames() == ["audio"], try loaded.outputNames() == ["features"] else {throw RVCSynthesisFailure.incompatibleModel}
            environment=env;session=loaded;snapshot=model
        } catch {try? FileManager.default.removeItem(at:model.deletingLastPathComponent());throw error}
    }
    func extract(_ audio:[Float]) throws -> [Float] {
        try Task.checkCancellation()
        guard audio.count == 147680, audio.allSatisfy({$0.isFinite && abs($0)<=1}) else {throw RVCSynthesisFailure.invalidInput}
        guard let session else {throw RVCSynthesisFailure.unavailable}
        let data=audio.withUnsafeBytes { NSMutableData(bytes:$0.baseAddress!,length:$0.count) }
        let value=try ORTValue(tensorData:data,elementType:.float,shape:[1,147680])
        let result=try withExtendedLifetime(data) {try session.run(withInputs:["audio":value],outputNames:["features"],runOptions:nil)}
        try Task.checkCancellation()
        guard let features=result["features"] else {throw RVCSynthesisFailure.invalidOutput}
        let info=try features.tensorTypeAndShapeInfo()
        let bytes=try features.tensorData()
        guard info.elementType == .float, info.shape.map({$0.intValue}) == [1,461,768],
              bytes.length == 461*768*4 else {throw RVCSynthesisFailure.invalidOutput}
        let copied=Array(UnsafeBufferPointer(start:bytes.bytes.assumingMemoryBound(to:Float.self),count:461*768))
        guard copied.allSatisfy({$0.isFinite}) else {throw RVCSynthesisFailure.invalidOutput}
        return copied
    }
    func close() {
        session=nil;environment=nil
        if let snapshot {try? FileManager.default.removeItem(at:snapshot.deletingLastPathComponent())}
        snapshot=nil
    }
    deinit {if let snapshot {try? FileManager.default.removeItem(at:snapshot.deletingLastPathComponent())}}
}
#endif
