"""Production playback method with controlled store/audio boundaries; no device audio claim."""
import pathlib, shutil, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class ReferencePlaybackOwnershipTests(unittest.TestCase):
 @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
 def test_delayed_reference_cannot_play_for_changed_selection(self):
  source=(ROOT/'VoiceMatrix/CharacterLibrary.swift').read_text()
  method=source[source.index('    func listenToReference('):source.index('    func review(')]
  # Completion instrumentation observes task exit without altering production decisions.
  method=method.replace('Task {', 'Task { defer { finished += 1 }', 1)
  selection=source[source.index('    @Published var selectedID'):source.index('    @Published var output:')].replace('@Published ', '')
  active=source[source.index('    func setApplicationActive('):source.index('    var engineAvailable:')]
  audio_source=(ROOT/'VoiceMatrix/AudioStore.swift').read_text()
  stop=audio_source[audio_source.index('    func stop()'):audio_source.index('    func save(')]
  harness='''import Foundation
struct Voice { let id: String; let referenceSHA256: String }
actor ReferenceStore {
 var pending: [CheckedContinuation<URL, Error>] = []
 var count: Int { pending.count }
 func referenceURL(id: String) async throws -> URL {
  try await withCheckedThrowingContinuation { pending.append($0) }
 }
 func finish(_ index: Int, failed: Bool = false) {
  if failed { pending[index].resume(throwing: NSError(domain: "fixture", code: 1)) }
  else { pending[index].resume(returning: URL(fileURLWithPath: "/synthetic/reference.wav")) }
 }
}
final class Player { func stop() {} }
@MainActor final class AudioStore {
 var playbackGeneration=UUID(); var player: Player?; var playing: URL?
 STOP
 var played: [URL] = []; var microphoneInUse = false; var processingInUse = false
 func play(_ url: URL) { played.append(url) }
}
@MainActor final class Harness {
 SELECTION
 init() { selectedID="one" }
 var busy = false; var profiles = [Voice(id:"one",referenceSHA256:"a")]
 var message = "unchanged"; var applicationActive = true; var referencePlaybackRequest = UUID()
 var syncing=false, catalogReachable=false; var lastCatalogAttempt: Date?; var syncJob: Task<Void,Never>?
 func releaseWarmSpeech() {}
 func cancelSync() {}
 func loadAndRefresh() async {}
 ACTIVE
 var finished = 0; let store = ReferenceStore()
 METHOD
}
@main struct Check {
 @MainActor static func main() async throws {
  var failures = 0
  func check(_ result: Bool, _ label: String) { if !result { print("FAIL: " + label); failures += 1 } }
  func wait(_ body: () async -> Bool) async throws {
   for _ in 0..<2000 { if await body() { return }; try await Task.sleep(nanoseconds:1_000_000) }
   throw NSError(domain:"fixture timeout",code:1)
  }
  for scenario in ["success","selection","removed","changedHash","busy","inactive","microphone","processing","newer","staleError","stopped","reactivated","reselected"] {
   let h=Harness(), audio=AudioStore()
   h.listenToReference(audio:audio)
   try await wait { await h.store.count == 1 }
   switch scenario {
    case "selection", "staleError": h.selectedID="other"
    case "removed": h.profiles=[]
    case "changedHash": h.profiles=[Voice(id:"one",referenceSHA256:"b")]
    case "busy": h.busy=true
    case "inactive": h.applicationActive=false
    case "microphone": audio.microphoneInUse=true
    case "processing": audio.processingInUse=true
    case "stopped": audio.stop()
    case "reselected": h.selectedID="other"; h.selectedID="one"
    case "reactivated": h.setApplicationActive(false); h.setApplicationActive(true)
    case "newer":
     h.listenToReference(audio:audio)
     try await wait { await h.store.count == 2 }
     await h.store.finish(1)
     try await wait { h.finished == 1 }
    default: break
   }
   await h.store.finish(0,failed:scenario == "staleError")
   try await wait { h.finished == (scenario == "newer" ? 2 : 1) }
   check(audio.played.count == (["success","newer"].contains(scenario) ? 1 : 0), scenario+" playback ownership")
   check(h.message == "unchanged", scenario+" status ownership")
  }
  if failures > 0 { exit(1) }
  print("Delayed reference playback: thirteen ownership scenarios passed; audio/store boundaries controlled")
 }
}
'''.replace('METHOD',method).replace('STOP',stop).replace('ACTIVE',active).replace('SELECTION',selection)
  with tempfile.TemporaryDirectory() as tmp:
   path=pathlib.Path(tmp); (path/'Checks.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(path/'Checks.swift'),'-o',str(path/'checks')],check=True,timeout=60)
   subprocess.run([str(path/'checks')],check=True,timeout=30)
