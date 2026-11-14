"""Native recorder callback logic with explicit controlled AVAudioFile/recorder boundaries."""
import pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RecorderCompletionTests(unittest.TestCase):
 def test_delegate_is_wired(self):
  s=(ROOT/'VoiceMatrix/Recording.swift').read_text()
  self.assertIn('NSObject, ObservableObject, AVAudioRecorderDelegate',s)
  self.assertIn('rec.delegate = self',s)
  self.assertIn('nonisolated func audioRecorderDidFinishRecording',s)
  self.assertIn('nonisolated func audioRecorderEncodeErrorDidOccur',s)
 @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler required')
 def test_callbacks_release_only_current_recorder(self):
  s=(ROOT/'VoiceMatrix/Recording.swift').read_text()
  self.assertIn('nonisolated func audioRecorderDidFinishRecording',s)
  callbacks=s[s.index('    nonisolated func audioRecorderDidFinishRecording'):s.index('\n}\nstruct RecordingView:')]
  callbacks=callbacks.replace('Task { @MainActor in','Task { @MainActor in defer { self.callbackFinished += 1 }')
  stop=s[s.index('    func stop()'):s.index('    func discard()')]
  harness='''import Foundation
final class AVAudioRecorder: NSObject, @unchecked Sendable { var stops=0; func stop() { stops += 1 } }
struct AVAudioFile {
 let length: Int
 init(forReading url: URL) throws { length=url.lastPathComponent == "empty" ? 0 : 100 }
}
@MainActor final class Harness {
 var recorder: AVAudioRecorder?; var recording=true; var timer: Task<Void,Never>?
 var requestID=UUID(); var output: URL? = URL(fileURLWithPath:"/synthetic/valid")
 var status="Recording"; var releases=0; var callbackFinished=0
 func releaseMicrophone() { releases += 1 }
 STOP
 CALLBACKS
}
@main struct Check {
 @MainActor static func main() async throws {
  var failures=0
  func check(_ x: Bool,_ message: String) { if !x { print("FAIL: "+message);failures += 1 } }
  for scenario in ["complete","failed","encode","empty","staleComplete","staleEncode","alreadyStopped"] {
   let h=Harness(), sender=AVAudioRecorder(), newer=AVAudioRecorder()
   h.recorder=sender
   if scenario == "empty" { h.output=URL(fileURLWithPath:"/synthetic/empty") }
   let stale=scenario.hasPrefix("stale") || scenario == "alreadyStopped"
   if scenario.hasPrefix("stale") { h.recorder=newer }
   if scenario == "alreadyStopped" { h.recorder=nil }
   if scenario == "encode" || scenario == "staleEncode" { h.audioRecorderEncodeErrorDidOccur(sender,error:nil) }
   else { h.audioRecorderDidFinishRecording(sender,successfully:scenario != "failed") }
   for _ in 0..<2000 { if h.callbackFinished>0 { break }; try await Task.sleep(nanoseconds:1_000_000) }
   check(h.callbackFinished==1, scenario+" callback completed")
   if stale {
    check(h.recording && h.releases==0 && h.status=="Recording",scenario+" cannot mutate newer state")
    check(newer.stops==0,scenario+" cannot stop newer recorder")
   } else {
    check(!h.recording && h.recorder==nil && h.releases==1,scenario+" releases microphone")
    check(sender.stops==1,scenario+" stops current recorder")
    if scenario == "empty" { check(h.output==nil && !h.status.contains("ready"),"empty output not ready") }
    else { check(h.output != nil,scenario+" retains usable output") }
    if scenario == "complete" { check(h.status=="Your original recording is ready.","completion status") }
    if scenario == "failed" || scenario == "encode" { check(!h.status.contains("is ready"),scenario+" not falsely ready") }
   }
  }
  if failures>0 { exit(1) }
  print("Seven recorder callback scenarios passed; microphone/file boundaries controlled")
 }
}
'''.replace('STOP',stop).replace('CALLBACKS',callbacks)
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp);(p/'Checks.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(p/'Checks.swift'),'-o',str(p/'checks')],check=True,timeout=60)
   subprocess.run([str(p/'checks')],check=True,timeout=30)
