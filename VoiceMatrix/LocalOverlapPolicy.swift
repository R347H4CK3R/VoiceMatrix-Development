import Foundation

/// Raw model speaker activity, independent of identity clustering. This veto is
/// conservative risk screening, not source separation or proof of a clean voice.
enum LocalOverlapPolicy {
    static let version = 1
    struct Evidence: Codable, Sendable, Equatable {
        let version: Int
        let sourceSHA256: String
        let modelRevision: String
        let duration: Double
        let frameDuration: Double
        let speakerSlots: Int
        /// -1 means uncovered/unknown. Zero is covered model silence, never missing.
        var counts: [Int]
    }
    enum Failure: Error { case invalidEvidence, resourceBound }
    static func build(weights: [[[Float]]], offsets: [Double], frameDuration: Double,
                      duration: Double, sourceSHA256: String, modelRevision: String) throws -> Evidence {
        guard duration.isFinite, duration > 0, duration <= 1800,
              frameDuration.isFinite, (0.001...1).contains(frameDuration),
              !weights.isEmpty, weights.count <= 2000, offsets.count == weights.count,
              offsets.allSatisfy({$0.isFinite && $0 >= 0 && $0 < duration}),
              zip(offsets,offsets.dropFirst()).allSatisfy({$0.0 < $0.1}),
              let first=weights.first?.first, (1...8).contains(first.count) else {throw Failure.invalidEvidence}
        let n=Int(ceil(duration/frameDuration)),slots=first.count
        guard n > 0,n <= 110_000,weights.reduce(0,{$0+$1.count}) <= 2_000_000 else {throw Failure.resourceBound}
        var sums=[Double](repeating:0,count:n),hits=[Int](repeating:0,count:n)
        for (chunk,rows) in weights.enumerated() {
            try Task.checkCancellation()
            guard !rows.isEmpty,rows.count <= 2000 else {throw Failure.invalidEvidence}
            for (frame,values) in rows.enumerated() {
                guard values.count==slots,values.allSatisfy({$0.isFinite && (0...1).contains($0)}) else {throw Failure.invalidEvidence}
                let start=offsets[chunk]+Double(frame)*frameDuration
                // Match the source-bounded reconstruction mapping, not padded EOF.
                guard start < duration else {continue}
                let mapped=(start/frameDuration).rounded()
                guard mapped >= 0,mapped < Double(n) else {continue}
                let i=Int(mapped)
                sums[i]+=values.reduce(0.0){$0+Double($1)};hits[i]+=1
            }
        }
        let counts=sums.indices.map {hits[$0]>0 ? Int((sums[$0]/Double(hits[$0])).rounded(.toNearestOrEven)) : -1}
        let evidence=Evidence(version:version,sourceSHA256:sourceSHA256,modelRevision:modelRevision,
            duration:duration,frameDuration:frameDuration,speakerSlots:slots,counts:counts)
        try validate(evidence)
        return evidence
    }
    static func validate(_ e: Evidence) throws {
        guard e.version==version,e.sourceSHA256.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
              !e.modelRevision.isEmpty,e.modelRevision.utf8.count <= 128,
              e.duration.isFinite,e.duration>0,e.duration<=1800,
              e.frameDuration.isFinite,(0.001...1).contains(e.frameDuration),
              (1...8).contains(e.speakerSlots),e.counts.count<=110_000,
              e.counts.count==Int(ceil(e.duration/e.frameDuration)),
              e.counts.allSatisfy({(-1...e.speakerSlots).contains($0)}) else {throw Failure.invalidEvidence}
    }
    static func allows(start: Double, end: Double, evidence e: Evidence) throws -> Bool {
        try validate(e)
        guard start.isFinite,end.isFinite,start>=0,end>start,end<=e.duration else {throw Failure.invalidEvidence}
        let lo=max(0,Int(floor(start/e.frameDuration))),hi=min(e.counts.count,Int(ceil(end/e.frameDuration)))
        guard lo<hi else {throw Failure.invalidEvidence}
        for i in lo..<hi where min(end,min(e.duration,Double(i+1)*e.frameDuration)) > max(start,Double(i)*e.frameDuration) {
            if e.counts[i] < 0 || e.counts[i] >= 2 {return false}
        }
        return true
    }
}
