#if canImport(OnnxRuntimeBindings) && canImport(CryptoKit)
import Foundation
import OnnxRuntimeBindings

/// Actual pinned Spleeter U-net inference. Experimental; not speaker identity or training.
actor VocalSeparationEngine {
    enum Failure:Error {case unavailable,invalidModel,invalidOutput}
    private var environment:ORTEnv?
    private var vocals:ORTSession?
    private var accompaniment:ORTSession?
    private var snapshot:URL?
    init(modelRoot:URL,cache:URL) throws {
        let owned=try VocalSeparationAssets.snapshot(root:modelRoot,cache:cache)
        do {
            let env=try ORTEnv(loggingLevel:.warning)
            let options=try ORTSessionOptions()
            try options.setIntraOpNumThreads(2)
            try options.setGraphOptimizationLevel(.all)
            // CPU only. No unverified CoreML provider or fp16 conversion.
            let v=try ORTSession(env:env,modelPath:owned.appendingPathComponent("vocals.onnx").path,sessionOptions:options)
            try Task.checkCancellation()
            let a=try ORTSession(env:env,modelPath:owned.appendingPathComponent("accompaniment.onnx").path,sessionOptions:options)
            for session in [v,a] {
                guard try session.inputNames()==["x"],try session.outputNames()==["y"] else {throw Failure.invalidModel}
            }
            try Task.checkCancellation()
            environment=env;vocals=v;accompaniment=a;snapshot=owned
        } catch {try? FileManager.default.removeItem(at:owned);throw error}
    }
    func separate(left:[Float],right:[Float]) throws -> VocalSeparationDSP.Stems {
        guard let vocals,let accompaniment else {throw Failure.unavailable}
        let prepared=try VocalSeparationDSP.prepare(left:left,right:right)
        let v=try run(vocals,magnitudes:prepared.magnitudes)
        let a=try run(accompaniment,magnitudes:prepared.magnitudes)
        return try VocalSeparationDSP.reconstruct(prepared:prepared,vocals:v,accompaniment:a)
    }
    private func run(_ session:ORTSession,magnitudes:[Float]) throws -> [Float] {
        try Task.checkCancellation()
        guard magnitudes.count==2*512*1024,magnitudes.allSatisfy({$0.isFinite && $0>=0}) else {throw Failure.invalidOutput}
        let data=magnitudes.withUnsafeBytes {NSMutableData(bytes:$0.baseAddress!,length:$0.count)}
        let tensor=try ORTValue(tensorData:data,elementType:.float,shape:[2,1,512,1024])
        let result=try withExtendedLifetime(data){try session.run(withInputs:["x":tensor],outputNames:["y"],runOptions:nil)}
        try Task.checkCancellation()
        guard let value=result["y"] else {throw Failure.invalidOutput}
        let info=try value.tensorTypeAndShapeInfo(),bytes=try value.tensorData()
        guard info.elementType == .float,info.shape.map({$0.intValue})==[2,1,512,1024],bytes.length==2*512*1024*4 else {throw Failure.invalidOutput}
        let copied=Array(UnsafeBufferPointer(start:bytes.bytes.assumingMemoryBound(to:Float.self),count:2*512*1024))
        guard copied.allSatisfy({$0.isFinite && $0>=0}) else {throw Failure.invalidOutput}
        return copied
    }
    func close() {
        vocals=nil;accompaniment=nil;environment=nil
        if let snapshot {try? FileManager.default.removeItem(at:snapshot)}
        snapshot=nil
    }
    deinit {if let snapshot {try? FileManager.default.removeItem(at:snapshot)}}
}
#endif
