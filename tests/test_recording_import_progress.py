"""Exercise the production import loop with controlled decoder progress and real temp files."""
import pathlib, shutil, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
class RecordingImportProgressTests(unittest.TestCase):
 @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
 def test_import_is_bounded_and_preserves_previous_audio_on_failure(self):
  source=(ROOT/'VoiceMatrix/Recording.swift').read_text()
  method=source[source.index('    func importAudio('):source.index('    nonisolated func audioRecorderDidFinishRecording')]
  harness=r'''import Foundation
let AVFormatIDKey="format", AVSampleRateKey="rate", AVNumberOfChannelsKey="channels", AVLinearPCMBitDepthKey="bits", AVLinearPCMIsFloatKey="float", kAudioFormatLinearPCM=1
extension URL { func startAccessingSecurityScopedResource()->Bool {true}; func stopAccessingSecurityScopedResource() {} }
enum StudioError: Error {case emptyAudio}
struct Format { var sampleRate=24000.0; var channelCount=1 }
var decoderMode=""
final class AVAudioPCMBuffer { var frameLength=0; init?(pcmFormat:Format,frameCapacity:Int) {if decoderMode == "allocation" {return nil}} }
final class AVAudioFile {
 var length=100; var framePosition=0; let mode:String
 var fileFormat=Format(); var processingFormat=Format()
 init(forReading url:URL)throws {mode=url.lastPathComponent;decoderMode=mode}
 init(forWriting url:URL,settings:[String:Any])throws {mode="writer";try Data("partial".utf8).write(to:url)}
 func read(into b:AVAudioPCMBuffer)throws {
  if mode == "stalled" {b.frameLength=0;return}
  if mode == "noPosition" {b.frameLength=100;return}
  b.frameLength=100;framePosition=100
 }
 func write(from b:AVAudioPCMBuffer)throws {}
}
enum TemporaryAudio {static func discard(_ u:URL?) {if let u {try? FileManager.default.removeItem(at:u)}}}
final class Harness {
 var recording=false;var output:URL?;var status=""
 METHOD
}
@main struct Check {
 static func main()throws {
  let scenario=CommandLine.arguments[1], h=Harness()
  let previous=FileManager.default.temporaryDirectory.appendingPathComponent("previous.wav")
  try Data("original".utf8).write(to:previous);h.output=previous
  h.importAudio(URL(fileURLWithPath:"/synthetic/"+scenario))
  if scenario == "valid" {
   precondition(h.output != previous && h.status.contains("ready"))
   precondition(!FileManager.default.fileExists(atPath:previous.path))
  } else {
   precondition(h.output == previous && !h.status.contains("ready"))
   precondition(try Data(contentsOf:previous) == Data("original".utf8))
   let files=try FileManager.default.contentsOfDirectory(atPath:FileManager.default.temporaryDirectory.path)
   precondition(!files.contains(where:{$0.hasPrefix("Imported-")}),"Partial import leaked")
  }
  print(scenario+" import check passed")
 }
}
'''.replace('METHOD',method).replace('precondition(try Data(contentsOf:previous) == Data("original".utf8))','let retained = try Data(contentsOf:previous); precondition(retained == Data("original".utf8))')
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp); (p/'Check.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(p/'Check.swift'),'-o',str(p/'check')],check=True,timeout=60)
   for scenario in ['stalled','noPosition','allocation','valid']:
    with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as audio:
     import os
     subprocess.run([str(p/'check'),scenario],env={**os.environ,'TMPDIR':audio},check=True,timeout=3)
