import Foundation

enum RVCNativePreparation {
    struct Noise {
        let latent: [Float]
        let phase: Float
        let excitation: [Float]
    }
    /// Explicit pitch input permits reference parity without silently selecting YIN.
    static func prepare(features:[Float], rawPitch:[Double], index:RVCNativeRetrieval?,
                        noise:Noise, semitones:Double = 0, indexRate:Float = 0.75) throws -> RVCSynthesisInputs {
        guard indexRate.isFinite, (0...1).contains(indexRate),
              features.count == 461*768, rawPitch.count >= 922, rawPitch.count <= 923 else {
            throw RVCSynthesisFailure.invalidInput
        }
        let pitch=try RVCFeaturePreparation.pitch(rawPitch,semitones:semitones)
        let hz=pitch.hz.prefix(922).map(Float.init)
        let neighbors:[Float]
        let distances:[Float]
        if indexRate == 0 {
            neighbors=[];distances=[]
        } else {
            guard let index else {throw RVCSynthesisFailure.invalidAsset}
            let found=try index.search(features)
            neighbors=found.vectors;distances=found.distances
        }
        let prepared=try RVCFeaturePreparation.features(features,rows:461,neighbors:neighbors,
            distances:distances,indexRate:indexRate,protect:0.33,pitchHz:hz)
        let result=RVCSynthesisInputs(phone:prepared.values,pitch:pitch.coarse.prefix(922).map(Int64.init),
            pitchHz:hz,latentNoise:noise.latent,phaseNoise:noise.phase,excitationNoise:noise.excitation)
        try result.validate()
        return result
    }
}

#if os(iOS)
/// Explicit experimental path; not exposed through production voice UI.
/// Caller supplies a preprocessed/reflected 147680-sample window and explicit noise.
actor RVCNativeWindowConverter {
    private var fileJobActive=false
    private let hubert:RVCONNXHuBERT
    private let synthesizer:RVCONNXSynthesizer
    private let index:RVCNativeRetrieval?
    init(hubert:RVCONNXHuBERT,synthesizer:RVCONNXSynthesizer,index:RVCNativeRetrieval?) {
        self.hubert=hubert;self.synthesizer=synthesizer;self.index=index
    }
    static func open(hubertRoot:URL,synthesizerRoot:URL,retrievalRoot:URL?,cache:URL) async throws -> RVCNativeWindowConverter {
        try RVCSynthesisAssets.validateRetrievalPair(RVCSynthesisAssets.manifest(at:synthesizerRoot),usesRetrieval:retrievalRoot != nil)
        let index=try retrievalRoot.map {try RVCNativeRetrieval.loadVerifiedDiagnosticPack(at:$0)}
        let hubert=try RVCONNXHuBERT(assetRoot:hubertRoot,cacheDirectory:cache)
        do {
            let synthesizer=try RVCONNXSynthesizer(assetRoot:synthesizerRoot,cacheDirectory:cache)
            return RVCNativeWindowConverter(hubert:hubert,synthesizer:synthesizer,index:index)
        } catch {await hubert.close();throw error}
    }
    func convertExperimentalAutocorrelation(_ audio:[Float], noise:RVCNativePreparation.Noise,
                                semitones:Double = 0, indexRate:Float = 0.75) async throws -> [Float] {
        try Task.checkCancellation()
        let pitch=try RVCNativePitch.experimentalAutocorrelation(audio)
        let features=try await hubert.extract(audio)
        let inputs=try RVCNativePreparation.prepare(features:features,rawPitch:pitch,index:index,noise:noise,semitones:semitones,indexRate:indexRate)
        return try await synthesizer.run(inputs)
    }
    func convertFileExperimentalAutocorrelation(input:URL,output:URL,scratch:URL,seed:UInt64,
                                    semitones:Double = 0,indexRate:Float = 0.75,
                                    progress:(Double)->Void = {_ in}) async throws -> RVCFileWorkflow.Result {
        guard !fileJobActive else {throw RVCSynthesisFailure.unavailable}
        fileJobActive=true
        defer {fileJobActive=false}
        return try await RVCFileWorkflow.convert(input:input,output:output,scratch:scratch,seed:seed,progress:progress) {window,noise in
            try await self.convertExperimentalAutocorrelation(window,noise:.init(latent:noise.latent,phase:noise.phase,excitation:noise.excitation),semitones:semitones,indexRate:indexRate)
        }
    }
    func convertMediaExperimentalAutocorrelation(input:URL,output:URL,scratch:URL,seed:UInt64,
                                    semitones:Double = 0,indexRate:Float = 0.75,
                                     progress:(Double)->Void = {_ in}) async throws -> RVCFileWorkflow.Result {
        guard !fileJobActive else {throw RVCSynthesisFailure.unavailable}
        guard !FileManager.default.fileExists(atPath:output.path) else {throw RVCFileError.destination}
        // Supported WAV files retain the tested rational resampler.
        if (try? RVCPCMReader(input)) != nil {
            return try await convertFileExperimentalAutocorrelation(input:input,output:output,scratch:scratch,seed:seed,semitones:semitones,indexRate:indexRate,progress:progress)
        }
        fileJobActive=true
        defer {fileJobActive=false}
        let folder=scratch.appendingPathComponent("rvc-import-"+UUID().uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        defer {try? FileManager.default.removeItem(at:folder)}
        let decoded=folder.appendingPathComponent("decoded.wav")
        try RVCAVAudioImport.decode(input:input,output:decoded)
        return try await RVCFileWorkflow.convert(input:decoded,output:output,scratch:scratch,seed:seed,progress:progress) {window,noise in
            try await self.convertExperimentalAutocorrelation(window,noise:.init(latent:noise.latent,phase:noise.phase,excitation:noise.excitation),semitones:semitones,indexRate:indexRate)
        }
    }
    func close() async {await hubert.close();await synthesizer.close()}
}
#endif
