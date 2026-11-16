import Foundation

/// Token softmax scores are not calibrated transcript correctness probabilities
/// and are not comparable to Apple's speech-segment confidence values.
enum BundledASRPolicy {
    /// Fixed recognition context for references only; never edits source samples.
    /// Inputs plus silence must remain within the existing 30-second ASR budget.
    static func referenceLeadingFrameCount(frames: Int, sampleRate: Double) -> Int? {
        guard sampleRate.isFinite, (16000...48000).contains(sampleRate),
              (1...1440000).contains(frames), Double(frames) / sampleRate >= 0.2 else { return nil }
        let lead = Int((sampleRate * 0.25).rounded())
        guard Double(frames + lead) / sampleRate <= 30 else { return nil }
        return lead
    }

    /// One input-boundary recovery only for an empty/punctuation-only decode.
    /// Original samples are retained; a 160 ms silent tail changes analysis context.
    static func recoveryTailFrameCount(text:String,samples:[Float],sampleRate:Double)->Int? {
        guard sampleRate.isFinite, (16000...48000).contains(sampleRate),
              !text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }),
              (1...1440000).contains(samples.count) else { return nil }
        let seconds=Double(samples.count)/sampleRate
        guard (2...29.84).contains(seconds), samples.allSatisfy({ $0.isFinite && abs($0)<=1 }) else { return nil }
        let energy=samples.reduce(0.0) { $0 + Double($1)*Double($1) }
        guard sqrt(energy/Double(samples.count)) >= 0.003 else { return nil }
        return Int((sampleRate*0.16).rounded())
    }
    static func admittedRecoveryTokenMean(_ scores:[Float])->Float? {
        guard let mean=admittedTokenMean(scores), mean>=0.7 else { return nil }
        return mean
    }
    static let minimumTokenMean: Float = 0.35
    static func admittedTokenMean(_ scores: [Float]) -> Float? {
        guard (1...4096).contains(scores.count), scores.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { return nil }
        let mean = scores.reduce(0, +) / Float(scores.count)
        return mean >= minimumTokenMean ? mean : nil
    }
}
