"""Patch only an isolated pinned vendor copy for the fixed licensed-speech controls."""
import argparse
import hashlib
import os
from pathlib import Path
import stat
import tempfile

MANAGER = Path("Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift")
PINNED_SHA256 = "db5cbe9fa368dce0524c50f9610bf848fc253e108ce99eaf702a66755f4000f7"

ORIGINAL_EXPORT_CALL = """        if let exportPath = config.embeddingExportPath {
            try exportEmbeddings(
                embeddings: timedEmbeddings,
                assignments: assignments,
                path: exportPath
            )
        }
"""
DIAGNOSTIC_EXPORT_CALL = """        if let exportPath = config.embeddingExportPath {
            try exportDiagnosticStages(
                embeddings: timedEmbeddings,
                embeddingFeatures: embeddingFeatures,
                assignments: assignments,
                trainingIndices: trainingIndices,
                initialClusters: initialClusters,
                vbxOutput: vbxOutput,
                centroidCount: centroids.count,
                path: exportPath
            )
        }
"""

ORIGINAL_EXPORT_START = "    private func exportEmbeddings(\n"
MANAGER_END = "\n}\n\n/// Owns the extractor"

DIAGNOSTIC_EXPORT = """    /// Probe-only scalar diagnostics. Executed after clustering and reconstruction.
    private func exportDiagnosticStages(
        embeddings: [TimedEmbedding],
        embeddingFeatures: [[Double]],
        assignments: [Int],
        trainingIndices: [Int],
        initialClusters: [Int],
        vbxOutput: VBxOutput,
        centroidCount: Int,
        path: String
    ) throws {
        struct Assignment: Encodable {
            let chunkIndex: Int
            let speakerIndex: Int
            let startFrame: Int
            let endFrame: Int
            let startTime: Double
            let endTime: Double
            let cluster: Int
        }

        struct PairwiseDistance: Encodable {
            let first: Int
            let second: Int
            let distance: Double
        }

        struct StageEvidence: Encodable {
            let embeddingCount: Int
            let finite256DCount: Int
            let embeddingNorms: [Double?]
            let pairwiseUnitEuclidean: [PairwiseDistance]
            let ahcTrainingIndices: [Int]
            let ahcInitialPartition: [Int]
            let vbxNumClusters: Int
            let vbxPiMasses: [Double?]
            let centroidCount: Int
        }

        struct DiagnosticExport: Encodable {
            let schemaVersion: Int
            let assignments: [Assignment]
            let stages: StageEvidence
        }

        // O(n²) scalar evidence is bounded for the fixed short clips. These guards
        // apply only to diagnostics, after the model and reconstruction have finished.
        let count = embeddings.count
        guard count <= 64, embeddingFeatures.count == count,
              trainingIndices.count == initialClusters.count, trainingIndices.count <= count,
              trainingIndices.allSatisfy({ embeddingFeatures.indices.contains($0) }),
              (0...64).contains(vbxOutput.numClusters), vbxOutput.pi.count <= 64,
              (0...64).contains(centroidCount) else {
            throw OfflineDiarizationError.exportFailed("Stage diagnostic exceeds its fixed clip bounds")
        }

        let norms = embeddingFeatures.map { vector -> Double? in
            guard vector.count == 256, vector.allSatisfy({ $0.isFinite }) else { return nil }
            let norm = sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
            return norm.isFinite ? norm : nil
        }
        var distances: [PairwiseDistance] = []
        distances.reserveCapacity(count * max(0, count - 1) / 2)
        for first in embeddingFeatures.indices {
            guard let firstNorm = norms[first] else { continue }
            let firstScale = firstNorm > 0 ? 1 / firstNorm : 0
            for second in (first + 1)..<count {
                guard let secondNorm = norms[second] else { continue }
                let secondScale = secondNorm > 0 ? 1 / secondNorm : 0
                // Same unit-normalized Euclidean metric as the inputs to AHC.
                let squareDistance = zip(embeddingFeatures[first], embeddingFeatures[second]).reduce(0.0) { sum, pair in
                    let delta = pair.0 * firstScale - pair.1 * secondScale
                    return sum + delta * delta
                }
                distances.append(PairwiseDistance(first: first, second: second, distance: sqrt(squareDistance)))
            }
        }

        let rows = embeddings.enumerated().map { index, embedding in
            Assignment(
                chunkIndex: embedding.chunkIndex, speakerIndex: embedding.speakerIndex,
                startFrame: embedding.startFrame, endFrame: embedding.endFrame,
                startTime: embedding.startTime, endTime: embedding.endTime,
                cluster: assignments.indices.contains(index) ? assignments[index] : -1
            )
        }
        let evidence = StageEvidence(
            embeddingCount: count, finite256DCount: norms.compactMap { $0 }.count, embeddingNorms: norms,
            pairwiseUnitEuclidean: distances, ahcTrainingIndices: trainingIndices, ahcInitialPartition: initialClusters,
            vbxNumClusters: vbxOutput.numClusters, vbxPiMasses: vbxOutput.pi.map { $0.isFinite ? $0 : nil },
            centroidCount: centroidCount
        )
        let payload = DiagnosticExport(schemaVersion: 1, assignments: rows, stages: evidence)
        let data = try JSONEncoder().encode(payload)
        guard data.count <= 262_144 else {
            throw OfflineDiarizationError.exportFailed("Stage diagnostic exceeds its byte bound")
        }
        try data.write(to: URL(fileURLWithPath: path), options: .withoutOverwriting)
    }
"""


def instrument(vendor_root):
    if vendor_root.is_symlink():
        raise ValueError("vendor copy root must not be a link")
    root = vendor_root.resolve(strict=True)
    repository = Path(__file__).resolve().parents[2]
    # A worktree uses a .git file; an ordinary checkout has a .git/HEAD.
    # An empty sandbox marker named .git is not a checkout.
    if (root == repository or repository in root.parents
            or any((parent / ".git").is_file() or (parent / ".git/HEAD").is_file()
                   for parent in (root, *root.parents))):
        raise ValueError("refusing to alter a repository checkout; supply a separate diagnostic copy")
    target = root / MANAGER
    if target.resolve(strict=True) != target or not target.is_file() or target.stat().st_nlink != 1:
        raise ValueError("manager in diagnostic copy must be an isolated regular file")
    original = target.read_bytes()
    if hashlib.sha256(original).hexdigest() != PINNED_SHA256:
        raise ValueError("diagnostic manager is not the pinned original source")
    swift = original.decode("utf-8")
    anchors = (ORIGINAL_EXPORT_CALL, ORIGINAL_EXPORT_START, MANAGER_END)
    if any(swift.count(anchor) != 1 for anchor in anchors):
        raise ValueError("expected exactly one of each pinned export anchor")
    call = swift.index(ORIGINAL_EXPORT_CALL)
    start = swift.index(ORIGINAL_EXPORT_START)
    end = swift.index(MANAGER_END)
    if not call < start < end:
        raise ValueError("pinned export anchors are out of order")
    patched = (swift[:call] + DIAGNOSTIC_EXPORT_CALL
               + swift[call + len(ORIGINAL_EXPORT_CALL):start] + DIAGNOSTIC_EXPORT + swift[end:])
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".diagnostic-manager-", delete=False) as handle:
            temporary = Path(handle.name)
            os.fchmod(handle.fileno(), stat.S_IMODE(target.stat().st_mode))
            handle.write(patched.encode("utf-8"))
            handle.flush()
            os.fsync(handle.fileno())
        if target.is_symlink() or target.stat().st_nlink != 1 or target.read_bytes() != original:
            raise ValueError("diagnostic manager changed during instrumentation")
        os.replace(temporary, target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print("Verified pinned copy; replaced only the export call/helper with scalar stage diagnostics.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("diagnostic_vendor_copy", type=Path)
    args = parser.parse_args()
    try:
        instrument(args.diagnostic_vendor_copy)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Cannot instrument diagnostic copy: {error}\n")


if __name__ == "__main__":
    main()
