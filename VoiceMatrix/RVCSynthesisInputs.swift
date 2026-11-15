import Foundation

enum RVCSynthesisFailure: Error { case invalidInput, invalidAsset, incompatibleModel, invalidOutput, unavailable }

struct RVCSynthesisInputs {
    var phone: [Float]
    var pitch: [Int64]
    var pitchHz: [Float]
    var latentNoise: [Float]
    var phaseNoise: Float
    var excitationNoise: [Float]
    struct Tensor {
        enum Kind { case float32, int64 }
        let bytes: Data
        let shape: [Int]
        let kind: Kind
    }
    func validate() throws {
        try Task.checkCancellation()
        guard phone.count == 922 * 768, pitch.count == 922, pitchHz.count == 922,
              latentNoise.count == 922 * 192, excitationNoise.count == 368800,
              phone.allSatisfy({ $0.isFinite }), pitch.allSatisfy({ (1...255).contains($0) }),
              pitchHz.allSatisfy({ $0.isFinite && $0 >= 0 }),
              latentNoise.allSatisfy({ $0.isFinite }), excitationNoise.allSatisfy({ $0.isFinite }),
              phaseNoise.isFinite, phaseNoise >= 0, phaseNoise < 1 else { throw RVCSynthesisFailure.invalidInput }
    }
    /// Buffer pointers are valid only during the callback. Consumers must copy
    /// into their owned runtime buffers before returning; no pointer escapes.
    func withTensorBytes(_ body: (String, UnsafeRawBufferPointer, [Int], Tensor.Kind) throws -> Void) throws {
        try validate()
        func floats(_ name: String, _ values: [Float], _ shape: [Int]) throws {
            try Task.checkCancellation()
            try values.withUnsafeBytes { try body(name, $0, shape, .float32) }
        }
        func integers(_ name: String, _ values: [Int64], _ shape: [Int]) throws {
            try Task.checkCancellation()
            try values.withUnsafeBytes { try body(name, $0, shape, .int64) }
        }
        try floats("phone", phone, [1,922,768])
        try integers("lengths", [922], [1])
        try integers("pitch", pitch, [1,922])
        try floats("pitchf", pitchHz, [1,922])
        try integers("speaker", [0], [1])
        try floats("latent_noise", latentNoise, [1,192,922])
        try floats("phase_noise", [phaseNoise], [1,1,1])
        try floats("excitation_noise", excitationNoise, [1,368800,1])
    }

    func tensors() throws -> [String: Tensor] {
        try validate()
        func floats(_ values: [Float], _ shape: [Int]) -> Tensor {
            Tensor(bytes: values.withUnsafeBytes { Data($0) }, shape: shape, kind: .float32)
        }
        func integers(_ values: [Int64], _ shape: [Int]) -> Tensor {
            Tensor(bytes: values.withUnsafeBytes { Data($0) }, shape: shape, kind: .int64)
        }
        return ["phone": floats(phone,[1,922,768]), "lengths": integers([922],[1]),
                "pitch": integers(pitch,[1,922]), "pitchf": floats(pitchHz,[1,922]),
                "speaker": integers([0],[1]), "latent_noise": floats(latentNoise,[1,192,922]),
                "phase_noise": floats([phaseNoise],[1,1,1]),
                "excitation_noise": floats(excitationNoise,[1,368800,1])]
    }
}
