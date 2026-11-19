// SPDX-License-Identifier: Apache-2.0
import Darwin
import Foundation
import Parakeet231

private enum CLIError: Error {
    case usage
    case oversizedInput
    case existingOutput
}

private struct Metadata: Encodable {
    let samples: Int
    let validSamples: Int
    let frames: Int
    let validFrames: Int
}

private func readBounded(_ path: String, maxBytes: Int) throws -> Data {
    let url = URL(fileURLWithPath: path)
    let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard attributes.isRegularFile == true, attributes.isSymbolicLink != true,
          let bytes = attributes.fileSize, bytes >= 0, bytes <= maxBytes else {
        throw CLIError.oversizedInput
    }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var data = Data(capacity: bytes)
    while data.count <= maxBytes {
        let remaining = maxBytes + 1 - data.count
        guard let block = try handle.read(upToCount: min(65_536, remaining)), !block.isEmpty else {
            return data
        }
        data.append(block)
    }
    throw CLIError.oversizedInput
}

private func run(_ args: [String]) throws {
    let required: Set<String> = ["--input", "--valid", "--window", "--filterbank", "--output", "--metadata"]
    guard args.count == required.count * 2 else { throw CLIError.usage }
    var parameters = [String: String]()
    for i in stride(from: 0, to: args.count, by: 2) {
        guard required.contains(args[i]), parameters[args[i]] == nil else { throw CLIError.usage }
        parameters[args[i]] = args[i + 1]
    }
    guard let raw = parameters["--input"], let validText = parameters["--valid"],
          let valid = Int(validText), let window = parameters["--window"],
          let filterbank = parameters["--filterbank"], let output = parameters["--output"],
          let metadata = parameters["--metadata"] else { throw CLIError.usage }
    let outputURL = URL(fileURLWithPath: output).standardizedFileURL
    let metadataURL = URL(fileURLWithPath: metadata).standardizedFileURL
    guard outputURL != metadataURL, !FileManager.default.fileExists(atPath: outputURL.path),
          !FileManager.default.fileExists(atPath: metadataURL.path) else { throw CLIError.existingOutput }

    let input = try readBounded(raw, maxBytes: 240_000 * 4)
    let pcm = try Parakeet231Frontend.readFloat32LE(input, count: input.count / 4)
    let frontend = try Parakeet231Frontend(windowLE: readBounded(window, maxBytes: 400 * 4),
                                          filterbankLE: readBounded(filterbank, maxBytes: 128 * 257 * 4))
    let result = try frontend.features(pcm, validSamples: valid)

    var encoded = Data(capacity: result.mel.count * 4)
    for value in result.mel {
        let bits = value.bitPattern
        for shift in stride(from: 0, to: 32, by: 8) {
            encoded.append(UInt8(truncatingIfNeeded: bits >> shift))
        }
    }
    let stats = Metadata(samples: pcm.count, validSamples: valid, frames: result.frames, validFrames: result.validFrames)
    let json = JSONEncoder()
    json.outputFormatting = [.sortedKeys]
    let encodedMetadata = try json.encode(stats)
    try encoded.write(to: outputURL, options: [.withoutOverwriting])
    try encodedMetadata.write(to: metadataURL, options: [.withoutOverwriting])
}

do {
    try run(Array(CommandLine.arguments.dropFirst()))
} catch {
    let message = "parakeet231-frontend failed: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
