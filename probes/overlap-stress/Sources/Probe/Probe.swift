import Foundation
import CryptoKit
@main struct Probe {
 static func main() async throws {
  let audio=URL(fileURLWithPath:CommandLine.arguments[2]);let expected=CommandLine.arguments[3]
  func hash() throws -> String { SHA256.hash(data:try Data(contentsOf:audio)).map{String(format:"%02x",$0)}.joined() }
  guard try hash()==expected else {fatalError("Fixture checksum mismatch")}
  let analysis=try await LocalSpeakerDiarization.analyze(source:audio,bundle:URL(fileURLWithPath:CommandLine.arguments[1])) { print($0) }
  try LocalSpeakerDiarization.validate(analysis)
  guard try hash()==expected else {fatalError("Original fixture changed")}
  try JSONEncoder().encode(analysis).write(to:URL(fileURLWithPath:CommandLine.arguments[4]))
 }
}
