import Foundation

/// Fixed Spleeter 2-stem spectral contract, not a separator without the trained models.
/// Deliberately Foundation-only radix-2 FFT: no platform-specific FFT scaling convention.
enum VocalSeparationDSP {
    enum Failure: Error { case input, prediction, shape, numeric }
    static let sampleRate = 44_100
    static let maximumFrames = 441_000
    static let fftSize = 4096
    static let hopSize = 1024
    static let modelFrames = 512
    static let modelBins = 1024
    static let tensorCount = 2 * modelFrames * modelBins

    struct Prepared {
        let magnitudes: [Float]
        let originalFrames: Int
        let frameCount: Int
        fileprivate let real: [[Double]]
        fileprivate let imag: [[Double]]
        fileprivate let paddedFrames: Int
    }
    struct Stems {
        let vocalsLeft: [Float]
        let vocalsRight: [Float]
        let accompanimentLeft: [Float]
        let accompanimentRight: [Float]
    }
    private static let window: [Double] = (0..<fftSize).map {
        0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(fftSize))
    }
    private static let reverse: [Int] = (0..<fftSize).map { value in
        var result=0, remaining=value
        for _ in 0..<12 {result=(result<<1)|(remaining&1);remaining >>= 1}
        return result
    }
    private static let rootsReal: [Double] = (0..<(fftSize/2)).map {cos(2 * Double.pi * Double($0) / Double(fftSize))}
    private static let rootsImag: [Double] = (0..<(fftSize/2)).map {sin(2 * Double.pi * Double($0) / Double(fftSize))}

    /// Unnormalized forward FFT; inverse applies exactly 1/N.
    private static func fft(real: inout [Double], imag: inout [Double], inverse: Bool) {
        for i in 0..<fftSize {
            let j=reverse[i]
            if i<j {real.swapAt(i,j);imag.swapAt(i,j)}
        }
        var length=2
        while length<=fftSize {
            let half=length/2, step=fftSize/length
            for start in stride(from:0,to:fftSize,by:length) {
                for offset in 0..<half {
                    let root=offset*step
                    let wr=rootsReal[root], wi=inverse ? rootsImag[root] : -rootsImag[root]
                    let a=start+offset, b=a+half
                    let br=real[b]*wr-imag[b]*wi, bi=real[b]*wi+imag[b]*wr
                    let ar=real[a], ai=imag[a]
                    real[a]=ar+br;imag[a]=ai+bi
                    real[b]=ar-br;imag[b]=ai-bi
                }
            }
            length *= 2
        }
        if inverse {
            for i in 0..<fftSize {real[i] /= Double(fftSize);imag[i] /= Double(fftSize)}
        }
    }

    /// Inputs are separate stereo channels, normalized finite PCM at exactly 44.1 kHz.
    /// A whole 4096-sample zero guard on each side protects Hann endpoints. The tail is
    /// padded to a complete hop, then outputs are cropped to the exact original length.
    static func prepare(left: [Float], right: [Float]) throws -> Prepared {
        try Task.checkCancellation()
        guard !left.isEmpty,left.count<=maximumFrames,left.count==right.count,
              left.allSatisfy({$0.isFinite && abs($0)<=1}),
              right.allSatisfy({$0.isFinite && abs($0)<=1}) else {throw Failure.input}
        let original=left.count
        let guardLength=original+2*fftSize
        let frameCount=1+(guardLength-fftSize+hopSize-1)/hopSize
        guard frameCount<=modelFrames else {throw Failure.shape}
        let padded=fftSize+(frameCount-1)*hopSize
        var magnitude=[Float](repeating:0,count:tensorCount)
        var reals=[[Double]](), imags=[[Double]]()
        for (channel,input) in [left,right].enumerated() {
            var savedReal=[Double](repeating:0,count:frameCount*modelBins)
            var savedImag=[Double](repeating:0,count:frameCount*modelBins)
            for frame in 0..<frameCount {
                try Task.checkCancellation()
                var real=[Double](repeating:0,count:fftSize)
                var imag=[Double](repeating:0,count:fftSize)
                for index in 0..<fftSize {
                    let source=frame*hopSize+index-fftSize
                    if source>=0 && source<original {real[index]=Double(input[source])*window[index]}
                }
                fft(real:&real,imag:&imag,inverse:false)
                let local=frame*modelBins, tensor=channel*modelFrames*modelBins+local
                for bin in 0..<modelBins {
                    savedReal[local+bin]=real[bin];savedImag[local+bin]=imag[bin]
                    let value=Float(hypot(real[bin],imag[bin]))
                    guard value.isFinite else {throw Failure.numeric}
                    magnitude[tensor+bin]=value
                }
            }
            reals.append(savedReal);imags.append(savedImag)
        }
        try Task.checkCancellation()
        return Prepared(magnitudes:magnitude,originalFrames:original,frameCount:frameCount,
                        real:reals,imag:imags,paddedFrames:padded)
    }

    /// Model outputs are predicted nonnegative magnitudes, not masks. This implements
    /// the published two-source squared-magnitude normalization, with epsilon split
    /// equally. Frequencies >=1024 bins are zero, so outputs are band-limited (~11 kHz).
    static func reconstruct(prepared: Prepared, vocals: [Float], accompaniment: [Float]) throws -> Stems {
        try Task.checkCancellation()
        guard vocals.count==tensorCount,accompaniment.count==tensorCount else {throw Failure.shape}
        guard vocals.allSatisfy({$0.isFinite && $0>=0}),
              accompaniment.allSatisfy({$0.isFinite && $0>=0}) else {throw Failure.prediction}
        var denominator=[Double](repeating:0,count:prepared.paddedFrames)
        for frame in 0..<prepared.frameCount {
            for i in 0..<fftSize {denominator[frame*hopSize+i] += window[i]*window[i]}
        }
        func channel(_ ch: Int, vocal: Bool) throws -> [Float] {
            var signal=[Double](repeating:0,count:prepared.paddedFrames)
            for frame in 0..<prepared.frameCount {
                try Task.checkCancellation()
                var real=[Double](repeating:0,count:fftSize)
                var imag=[Double](repeating:0,count:fftSize)
                let local=frame*modelBins, tensor=ch*modelFrames*modelBins+local
                for bin in 0..<modelBins {
                    let v=Double(vocals[tensor+bin]), a=Double(accompaniment[tensor+bin])
                    let power=vocal ? v*v : a*a
                    let mask=(power+5e-11)/(v*v+a*a+1e-10)
                    real[bin]=prepared.real[ch][local+bin]*mask
                    imag[bin]=prepared.imag[ch][local+bin]*mask
                    if bin>0 {real[fftSize-bin]=real[bin];imag[fftSize-bin] = -imag[bin]}
                }
                fft(real:&real,imag:&imag,inverse:true)
                for i in 0..<fftSize {signal[frame*hopSize+i] += real[i]*window[i]}
            }
            var result=[Float](repeating:0,count:prepared.originalFrames)
            for i in 0..<prepared.originalFrames {
                let offset=i+fftSize
                guard denominator[offset]>0 else {throw Failure.numeric}
                let value=Float(signal[offset]/denominator[offset])
                guard value.isFinite else {throw Failure.numeric}
                result[i]=value
            }
            return result
        }
        let vl=try channel(0,vocal:true), vr=try channel(1,vocal:true)
        let al=try channel(0,vocal:false), ar=try channel(1,vocal:false)
        try Task.checkCancellation()
        return Stems(vocalsLeft:vl,vocalsRight:vr,accompanimentLeft:al,accompanimentRight:ar)
    }
}
