import Foundation
@main struct Probe {
 static func main() async throws {
  let input=URL(fileURLWithPath:CommandLine.arguments[1]), output=URL(fileURLWithPath:CommandLine.arguments[2])
  let evidence=try await LocalSoundQuality.analyze(source:input) { _ in }
  let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys]
  try encoder.encode(evidence).write(to:output,options:.atomic)
 }
}
