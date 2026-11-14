import Foundation

/// Non-neural CPU stages for the pinned RVC v2 pipeline, float32 feature path.
/// Derived from RVC-Project, revision 81eed5e8f68b6bed1789f682fe78cdd324495afc,
/// infer/vc/pipeline.py (get_f0 and vc). See LICENSES/RVC-MIT.txt.
/// Call after pitch extraction / encoder / neighbor search, before synthesis.
/// This does not extract pitch, search an index, load weights or generate audio.
enum RVCFeaturePreparation {
    enum Failure: Error { case shape, value, numerical }
    struct Pitch: Sendable { let hz: [Double]; let coarse: [Int32] }
    struct Features: Sendable { let values: [Float]; let frames: Int }
    static let dimensions = 768
    static let neighborsPerRow = 8
    static let maximumRows = 1_500

    /// Matches upstream's zero-gap interpolation, including constant endpoint fill,
    /// semitone shift, mel mapping and NumPy's ties-to-even quantization.
    /// Entirely unvoiced input stays zero Hz with coarse bin 1.
    static func pitch(_ extracted: [Double], semitones: Double) throws -> Pitch {
        try Task.checkCancellation()
        guard !extracted.isEmpty, extracted.count <= maximumRows * 2 else { throw Failure.shape }
        guard semitones.isFinite, (-24...24).contains(semitones),
              extracted.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw Failure.value }
        let voiced = extracted.indices.filter { extracted[$0] > 0 }
        var continuous = extracted
        if let first = voiced.first, let last = voiced.last {
            for index in 0..<first { continuous[index] = extracted[first] }
            for index in (last + 1)..<extracted.count { continuous[index] = extracted[last] }
            for pair in zip(voiced, voiced.dropFirst()) where pair.1 > pair.0 + 1 {
                let slope = (extracted[pair.1] - extracted[pair.0]) / Double(pair.1 - pair.0)
                for index in (pair.0 + 1)..<pair.1 {
                    continuous[index] = extracted[pair.0] + slope * Double(index - pair.0)
                }
            }
        }
        let shift = pow(2.0, semitones / 12)
        let lower = 1127 * log(1 + 50.0 / 700)
        let upper = 1127 * log(1 + 1100.0 / 700)
        var coarse: [Int32] = []
        coarse.reserveCapacity(continuous.count)
        for index in continuous.indices {
            try Task.checkCancellation()
            continuous[index] *= shift
            guard continuous[index].isFinite, Float(continuous[index]).isFinite else { throw Failure.numerical }
            var mel = 1127 * log(1 + continuous[index] / 700)
            if mel > 0 { mel = (mel - lower) * 254 / (upper - lower) + 1 }
            coarse.append(Int32(min(255, max(1, mel)).rounded(.toNearestOrEven)))
        }
        return Pitch(hz: continuous, coarse: coarse)
    }

    /// Flat row-major [rows,768], [rows,8,768], [rows,8] and [2*rows].
    /// Distances are the positive squared-L2 scores returned by the upstream
    /// neighbor search: upstream squares their reciprocal again for weighting.
    /// Uses nearest-neighbor 2x frame expansion (not linear interpolation).
    /// Callers supply already aligned continuous pitch; no voicing is inferred.
    /// With indexRate zero, neighbors/distances are unused and may be empty.
    static func features(_ original: [Float], rows: Int,
                         neighbors: [Float], distances: [Float],
                         indexRate: Float, protect: Float, pitchHz: [Float]) throws -> Features {
        try Task.checkCancellation()
        // Bound dimensions before multiplying, allocating or scanning payload arrays.
        guard (1...maximumRows).contains(rows),
              original.count == rows * dimensions,
              pitchHz.count == rows * 2 else { throw Failure.shape }
        guard indexRate.isFinite, (0...1).contains(indexRate),
              protect.isFinite, (0...0.5).contains(protect),
              pitchHz.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw Failure.value }
        if indexRate != 0 {
            guard neighbors.count == rows * neighborsPerRow * dimensions,
                  distances.count == rows * neighborsPerRow else { throw Failure.shape }
        }
        var output = [Float](repeating: 0, count: rows * 2 * dimensions)
        for row in 0..<rows {
            try Task.checkCancellation()
            if indexRate == 0 {
                for dimension in 0..<dimensions {
                    let value = original[row * dimensions + dimension]
                    guard value.isFinite else { throw Failure.value }
                    output[row * 2 * dimensions + dimension] = value
                    output[(row * 2 + 1) * dimensions + dimension] = value
                }
                continue
            }
            var weights = [Float](repeating: 0, count: neighborsPerRow)
            var sum: Float = 0
            for neighbor in 0..<neighborsPerRow {
                let distance = distances[row * neighborsPerRow + neighbor]
                guard distance.isFinite, distance > 0 else { throw Failure.value }
                let inverse: Float = 1 / distance
                let weight = inverse * inverse
                guard weight.isFinite, weight > 0 else { throw Failure.numerical }
                weights[neighbor] = weight
                sum += weight
            }
            guard sum.isFinite, sum > 0 else { throw Failure.numerical }
            for neighbor in weights.indices { weights[neighbor] /= sum }
            for dimension in 0..<dimensions {
                let source = original[row * dimensions + dimension]
                guard source.isFinite else { throw Failure.value }
                var retrieved: Float = 0
                for neighbor in 0..<neighborsPerRow {
                    let value = neighbors[(row * neighborsPerRow + neighbor) * dimensions + dimension]
                    guard value.isFinite else { throw Failure.value }
                    retrieved += value * weights[neighbor]
                }
                let mixed = retrieved * indexRate + (1 - indexRate) * source
                guard mixed.isFinite else { throw Failure.numerical }
                for duplicate in 0..<2 {
                    let frame = row * 2 + duplicate
                    // Upstream uses pitch < 1, including small positive values.
                    let mask: Float = protect < 0.5 && pitchHz[frame] < 1 ? protect : 1
                    let value = protect < 0.5 ? mixed * mask + source * (1 - mask) : mixed
                    guard value.isFinite else { throw Failure.numerical }
                    output[frame * dimensions + dimension] = value
                }
            }
        }
        try Task.checkCancellation()
        return Features(values: output, frames: rows * 2)
    }
}
