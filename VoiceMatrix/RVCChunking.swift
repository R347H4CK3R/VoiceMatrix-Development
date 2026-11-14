import Foundation

/// CPU-tested building block for a future iPhone RVC engine; no model runtime is implied.
enum RVCChunkError: Error { case invalidInput, invalidChunk, cancelled }

struct RVCChunkPlan {
    struct Chunk { let start: Int; let count: Int; let inputStart: Int }
    let inputSamples: Int
    let outputSamples: Int
    let count: Int
    init(inputSamples: Int) throws {
        guard (960...115_200_000).contains(inputSamples) else { throw RVCChunkError.invalidInput }
        self.inputSamples = inputSamples
        outputSamples = (inputSamples * 5 + 1) / 2
        count = outputSamples <= 240_000 ? 1 : 1 + (outputSamples - 240_000 + 231_999) / 232_000
    }
    func chunk(_ index: Int) throws -> Chunk {
        guard index >= 0 && index < count else { throw RVCChunkError.invalidChunk }
        let start = index * 232_000
        return Chunk(start: start, count: min(240_000, outputSamples - start), inputStart: index * 92_800)
    }
    func reflectedInputIndex(chunk index: Int, offset: Int) throws -> Int {
        guard (0..<147_680).contains(offset) else { throw RVCChunkError.invalidInput }
        let position = try chunk(index).inputStart - 16_000 + offset
        let period = 2 * (inputSamples - 1)
        let remainder = (position % period + period) % period
        return min(remainder, period - remainder)
    }
}

/// Serial caller owns output persistence; retain only one core while mixing.
final class RVCChunkReconstructor {
    private let plan: RVCChunkPlan
    private var nextIndex = 0
    private var pending: [Float] = []
    init(plan: RVCChunkPlan) { self.plan = plan }
    func append(_ core: [Float], cancelled: () -> Bool = { false }) throws -> [Float] {
        if cancelled() { throw RVCChunkError.cancelled }
        let chunk = try plan.chunk(nextIndex)
        guard core.count == chunk.count && core.allSatisfy({ $0.isFinite }) else { throw RVCChunkError.invalidChunk }
        var mixed = core
        var finalized: [Float] = []
        if nextIndex > 0 {
            let previous = try plan.chunk(nextIndex - 1)
            let overlap = previous.start + previous.count - chunk.start
            guard overlap > 1 && overlap <= pending.count && overlap <= core.count else { throw RVCChunkError.invalidChunk }
            finalized = Array(pending.dropLast(overlap))
            for i in 0..<overlap {
                let weight = Float(i) / Float(overlap - 1)
                mixed[i] = pending[pending.count - overlap + i] * (1 - weight) + core[i] * weight
            }
        }
        if cancelled() { throw RVCChunkError.cancelled }
        nextIndex += 1
        if nextIndex == plan.count {
            finalized.append(contentsOf: mixed)
            pending = []
        } else { pending = mixed }
        return finalized
    }
    var isComplete: Bool { nextIndex == plan.count }
}
