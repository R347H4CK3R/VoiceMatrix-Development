// SPDX-License-Identifier: Apache-2.0
// Standalone original-NeMo-2.3.1 mathematical frontend prototype.
// See README for upstream attribution and scope.
import Accelerate
import CryptoKit
import Foundation

public struct Parakeet231Features: Equatable {
    /// Bin-major ordering: mel[bin * frames + frame].
    public let mel: [Float]
    public let frames: Int
    public let validFrames: Int
}

public enum Parakeet231Error: Error, Equatable {
    case invalidBufferSize
    case invalidBufferValue
    case originalBufferDigestMismatch
    case unsupportedAudioLength
    case unsupportedValidSamples
    case nonfiniteAudio
    case transformUnavailable
    case nonfiniteResult
}

/// CPU frontend for batch size one; frame and FFT arithmetic is Double.
/// The input is already Float32 PCM, and mel output is cast once after normalization.
/// This does not reproduce old FP32 reduction artifacts.
public struct Parakeet231Frontend: Sendable {
    public static let minAudioSamples = 257
    public static let maxAudioSamples = 240_000
    public static let minValidSamples = 160
    public static let melBins = 128
    private static let windowLength = 400
    private static let fftLength = 512
    private static let spectralBins = fftLength / 2 + 1
    private static let hop = 160
    private static let logGuard = 1.0 / 16_777_216.0
    private static let windowSHA256 = "744788a137aa808ccc97d9d3c185c649b2e9c2b99c3262887c3ac9bb3b7e1c4c"
    private static let filterbankSHA256 = "f5608e00763a20a191022fbb00a43346db5f1ec06828a97a6f4157f7d02b76c8"

    private let window: [Double]
    private let filterbank: [Double]

    /// Require the exact original NVIDIA-provenance buffers; no checkpoint loader or downloads.
    public init(windowLE: Data, filterbankLE: Data) throws {
        guard windowLE.count == Self.windowLength * 4,
              filterbankLE.count == Self.melBins * Self.spectralBins * 4 else {
            throw Parakeet231Error.invalidBufferSize
        }
        guard Self.sha256(windowLE) == Self.windowSHA256,
              Self.sha256(filterbankLE) == Self.filterbankSHA256 else {
            throw Parakeet231Error.originalBufferDigestMismatch
        }
        try self.init(analyticWindowLE: windowLE, analyticFilterbankLE: filterbankLE)
    }

    // Internal only: checked analytic vectors for the test target.
    init(analyticWindowLE: Data, analyticFilterbankLE: Data) throws {
        let w = try Self.readFloat32LE(analyticWindowLE, count: Self.windowLength)
        let f = try Self.readFloat32LE(analyticFilterbankLE, count: Self.melBins * Self.spectralBins)
        guard w.allSatisfy({ $0.isFinite }),
              f.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw Parakeet231Error.invalidBufferValue
        }
        window = w.map { Double($0) }
        filterbank = f.map { Double($0) }
    }

    static func sha256(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public static func readFloat32LE(_ data: Data, count: Int) throws -> [Float] {
        guard count >= 0, count <= Int.max / 4, data.count == count * 4 else {
            throw Parakeet231Error.invalidBufferSize
        }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var floats = [Float]()
            floats.reserveCapacity(count)
            for i in stride(from: 0, to: raw.count, by: 4) {
                let word = raw.loadUnaligned(fromByteOffset: i, as: UInt32.self)
                floats.append(Float(bitPattern: UInt32(littleEndian: word)))
            }
            return floats
        }
    }

    public func features(_ audio: [Float], validSamples: Int) throws -> Parakeet231Features {
        let n = audio.count
        guard (Self.minAudioSamples...Self.maxAudioSamples).contains(n) else {
            throw Parakeet231Error.unsupportedAudioLength
        }
        guard (Self.minValidSamples...n).contains(validSamples) else {
            throw Parakeet231Error.unsupportedValidSamples
        }
        guard audio.allSatisfy({ $0.isFinite }) else {
            throw Parakeet231Error.nonfiniteAudio
        }
        let frames = n / Self.hop + 1
        let validFrames = validSamples / Self.hop + 1
        let count = Self.fftLength
        let bins = Self.spectralBins
        let half = count / 2
        let windowInset = (count - Self.windowLength) / 2

        guard let dft = vDSP_DFT_zop_CreateSetupD(nil, vDSP_Length(count), .FORWARD) else {
            throw Parakeet231Error.transformUnavailable
        }
        defer { vDSP_DFT_DestroySetupD(dft) }

        // NeMo 2.3.1 uses global preemphasis before reflect padding.
        // Preserve the entire supplied waveform, including any nonzero data beyond validSamples.
        var emphasized = [Double](repeating: 0, count: n)
        emphasized[0] = Double(audio[0])
        for i in 1..<n {
            emphasized[i] = Double(audio[i]) - 0.97 * Double(audio[i - 1])
        }
        // Only valid frames are needed: normalization ignores later frames and the
        // returned array initializes that entire suffix to exact positive zero.
        var power = [Double](repeating: 0, count: bins * validFrames)
        var re = [Double](repeating: 0, count: count)
        let im = [Double](repeating: 0, count: count)
        var outRe = [Double](repeating: 0, count: count)
        var outIm = [Double](repeating: 0, count: count)

        for frame in 0..<validFrames {
            let start = frame * Self.hop - half
            // The surrounding 56 samples on each side remain zero (centered STFT window).
            for w in 0..<Self.windowLength {
                let i = start + windowInset + w
                let source: Int
                if i < 0 {
                    source = -i
                } else if i >= n {
                    source = 2 * (n - 1) - i
                } else {
                    source = i
                }
                re[windowInset + w] = emphasized[source] * window[w]
            }
            // Complex DFT of real input avoids packed-real Nyquist/sign or scaling conventions.
            // Keep only nonnegative frequencies including both DC and Nyquist.
            vDSP_DFT_ExecuteD(dft, re, im, &outRe, &outIm)
            for bin in 0..<bins {
                let a = outRe[bin], b = outIm[bin]
                power[bin * validFrames + frame] = a * a + b * b
            }
        }
        var energy = [Double](repeating: 0, count: Self.melBins * validFrames)
        vDSP_mmulD(filterbank, 1, power, 1, &energy, 1,
                   vDSP_Length(Self.melBins), vDSP_Length(validFrames), vDSP_Length(bins))

        var mel = [Float](repeating: 0, count: Self.melBins * frames)
        let len = Double(validFrames)
        for bin in 0..<Self.melBins {
            let inputBase = bin * validFrames
            let outputBase = bin * frames
            let anchor = log(energy[inputBase] + Self.logGuard)
            var sum = 0.0
            for frame in 0..<validFrames {
                let centered = log(energy[inputBase + frame] + Self.logGuard) - anchor
                energy[inputBase + frame] = centered
                sum += centered
            }
            let mean = sum / len
            var squareSum = 0.0
            for frame in 0..<validFrames {
                let delta = energy[inputBase + frame] - mean
                energy[inputBase + frame] = delta
                squareSum += delta * delta
            }
            let stdWithEpsilon = sqrt(squareSum / (len - 1)) + 0.00001
            for frame in 0..<validFrames {
                let x = Float(energy[inputBase + frame] / stdWithEpsilon)
                guard x.isFinite else { throw Parakeet231Error.nonfiniteResult }
                mel[outputBase + frame] = x
            }
        }
        return Parakeet231Features(mel: mel, frames: frames, validFrames: validFrames)
    }
}
