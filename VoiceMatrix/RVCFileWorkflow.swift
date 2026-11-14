import Foundation

enum RVCFileWorkflow {
    struct Noise {let latent:[Float];let phase:Float;let excitation:[Float]}
    struct Result: Sendable {let samples:Int;let gain:Float;let chunks:Int;let inputGain:Float;let inputPeak:Float}
    /// Deterministic normal noise for the model's explicit-noise contract.
    /// This is not PyTorch RNG seed parity.
    struct Generator {
        var state:UInt64
        mutating func uniform()->Double {
            state &+= 0x9e3779b97f4a7c15
            var z=state;z=(z^(z>>30)) &* 0xbf58476d1ce4e5b9;z=(z^(z>>27)) &* 0x94d049bb133111eb
            z ^= z>>31
            return (Double(z>>11)+0.5)/9007199254740992.0
        }
        mutating func normal(_ count:Int)->[Float] {
            var values:[Float]=[];values.reserveCapacity(count)
            while values.count<count {
                let radius=sqrt(-2*log(uniform())),angle=2*Double.pi*uniform()
                values.append(Float(radius*cos(angle)))
                if values.count<count {values.append(Float(radius*sin(angle)))}
            }
            return values
        }
        mutating func noise()->Noise {
            let latent=normal(922*192)
            // Double-to-Float rounding must not turn a uniform sample into 1.
            let phase=min(Float(uniform()),Float(1).nextDown)
            return Noise(latent:latent,phase:phase,excitation:normal(368800))
        }
    }
    static func convert(input:URL,output:URL,scratch:URL,seed:UInt64,
                        progress:(Double)->Void = {_ in},
                        synthesize:([Float],Noise) async throws -> [Float]) async throws -> Result {
        let fm=FileManager.default
        guard !fm.fileExists(atPath:output.path),input.standardizedFileURL != output.standardizedFileURL else {throw RVCFileError.destination}
        try Task.checkCancellation()
        let job=scratch.appendingPathComponent("rvc-job-"+UUID().uuidString,isDirectory:true)
        try fm.createDirectory(at:job,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        let partial=output.deletingLastPathComponent().appendingPathComponent(".rvc-"+UUID().uuidString+".partial")
        defer {try? fm.removeItem(at:job);try? fm.removeItem(at:partial)}
        progress(0)
        let prepared=try RVCFilePreprocessor.prepare(input:input,directory:job)
        progress(0.15)
        let reader=try RVCFloatReader(prepared.url,samples:prepared.samples)
        let plan=try RVCChunkPlan(inputSamples:prepared.samples)
        let mixer=RVCChunkReconstructor(plan:plan)
        let rawURL=job.appendingPathComponent("converted.f32")
        let raw=try RVCFileIO.create(rawURL)
        defer {try? raw.close()}
        var peak:Float=0;var written=0
        var random=Generator(state:seed)
        for i in 0..<plan.count {
            try Task.checkCancellation()
            let window=try reader.window(plan:plan,index:i)
            let result=try await synthesize(window,random.noise())
            try Task.checkCancellation()
            guard result.count==368800,result.allSatisfy({$0.isFinite}) else {throw RVCFileError.nonfinite}
            let chunk=try plan.chunk(i)
            let core=Array(result[40000..<(40000+chunk.count)])
            let finalized=try mixer.append(core,cancelled:{Task.isCancelled})
            if let p=finalized.map({abs($0)}).max() {peak=max(peak,p)}
            written += finalized.count
            try RVCFileIO.write(finalized,to:raw)
            progress(0.15+0.75*Double(i+1)/Double(plan.count))
        }
        guard mixer.isComplete,written==plan.outputSamples else {throw RVCFileError.bounds}
        try raw.synchronize()
        let gain=peak>0.99 ? 0.99/peak : 1
        let destination=try RVCFileIO.create(partial)
        defer {try? destination.close()}
        var header=Data()
        func text(_ s:String) {header.append(contentsOf:s.utf8)}
        func u32(_ v:UInt32) {var x=v.littleEndian;withUnsafeBytes(of:&x){header.append(contentsOf:$0)}}
        func u16(_ v:UInt16) {var x=v.littleEndian;withUnsafeBytes(of:&x){header.append(contentsOf:$0)}}
        text("RIFF");u32(UInt32(36+written*2));text("WAVEfmt ");u32(16);u16(1);u16(1);u32(40000);u32(80000);u16(2);u16(16);text("data");u32(UInt32(written*2))
        try destination.write(contentsOf:header)
        let outputReader=try RVCFloatReader(rawURL,samples:written)
        for start in stride(from:0,to:written,by:16384) {
            try Task.checkCancellation()
            let values=try outputReader.read(start,min(16384,written-start))
            let pcm=values.map {Int16(($0*gain*32767).rounded()).littleEndian}
            try RVCFileIO.write(pcm,to:destination)
        }
        try destination.synchronize();try destination.close()
        try Task.checkCancellation()
        // FileManager refuses to replace an existing destination.
        try fm.moveItem(at:partial,to:output)
        progress(1)
        return Result(samples:written,gain:gain,chunks:plan.count,inputGain:prepared.inputGain,inputPeak:prepared.peakBeforeGain)
    }
}
