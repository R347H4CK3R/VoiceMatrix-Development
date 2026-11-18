"""Execute exact status/finish methods with real disk failures; not full iOS coordinator."""
import pathlib, re, shutil, subprocess, tempfile, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]

class CompletionTransactionTests(unittest.TestCase):
 @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
 def test_completion_commits_only_with_persisted_status(self):
  source = (ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  start = source.index('    private func update(')
  end = source.index('\n    }', start) + len('\n    }')
  update = source[start:end]
  self.assertNotIn('verifiedMKVExport', update)
  self.assertIn('LocalStudioSnapshot.encode', update)
  finish = re.search(r'(?:current\?\.completed = saved[^\n]*\n\s*)?try update\(unresolved == 0[^\n]*', source).group(0)
  harness = '''import Foundation
final class StatusHarness {
 typealias Event = LocalStudioJournal.Event
 struct Job: Codable {
  var updated = Date(); var stage = "Working"; var message = "Retained"
  var completed = false; var events: [Event] = []
 }
 var current: Job? = Job(); var notice = "Retained"; let folder: URL
 init(_ folder: URL) { self.folder = folder }
 UPDATE
 func record(_ message: String) throws { try update("Working", message) }
 func finish(saved: Int, unresolved: Int) throws { FINISH }
}
@main struct Check {
 static func main() throws {
  let fm = FileManager.default
  let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fm.createDirectory(at: root, withIntermediateDirectories: true)
  defer { try? fm.removeItem(at: root) }
  var failures = 0
  func check(_ result: Bool, _ text: String) { if !result { print("FAIL: " + text); failures += 1 } }
  for failure in ["snapshot", "journal", "none", "partial"] {
   let folder = root.appendingPathComponent(failure)
   try fm.createDirectory(at: folder, withIntermediateDirectories: true)
   let h = StatusHarness(folder)
   if failure == "snapshot" { try fm.createDirectory(at: folder.appendingPathComponent("job.json"), withIntermediateDirectories: false) }
   if failure == "journal" { try fm.createDirectory(at: folder.appendingPathComponent(LocalStudioJournal.filename), withIntermediateDirectories: false) }
   do {
    try h.finish(saved: 1, unresolved: failure == "partial" ? 1 : 0)
    check(failure == "none" || failure == "partial", "disk failure was swallowed")
    let persisted = try JSONDecoder().decode(StatusHarness.Job.self, from: Data(contentsOf: folder.appendingPathComponent("job.json")))
    check(persisted.completed == (failure == "none"), "persisted completion")
    check(h.current?.completed == persisted.completed, "memory/disk agreement")
   } catch {
    check(failure == "snapshot" || failure == "journal", "unexpected write failure")
    check(h.current?.completed == false, "failed " + failure + " must remain resumable")
    check(h.current?.stage == "Working", "failed write must not commit status")
    // Repair only the deliberately invalid fixture and retry the real method.
    let blocked = folder.appendingPathComponent(failure == "snapshot" ? "job.json" : LocalStudioJournal.filename)
    try fm.removeItem(at: blocked)
    try h.finish(saved: 1, unresolved: 0)
    check(h.current?.completed == true, "retry completion")
    let persisted = try JSONDecoder().decode(StatusHarness.Job.self, from: Data(contentsOf: folder.appendingPathComponent("job.json")))
    check(persisted.completed, "retry persisted")
   }
  }
  let verbose=root.appendingPathComponent("verbose")
  try fm.createDirectory(at:verbose,withIntermediateDirectories:false)
  let longJob=StatusHarness(verbose)
  let message=String(repeating:"x",count:1900)
  for _ in 0..<160 { try longJob.record(message) }
  let snapshot=try Data(contentsOf:verbose.appendingPathComponent("job.json"))
  check(snapshot.count<=262_144,"snapshot exceeds history reload bound")
  let restored=try JSONDecoder().decode(StatusHarness.Job.self,from:snapshot)
  check(!restored.events.isEmpty && restored.events.last?.message==message,"latest event lost")
  check(restored.events.count==longJob.current?.events.count,"snapshot and live events differ")
  let journal=try LocalStudioJournal.read(folder:verbose)
  check(journal.total==160,"complete journal was truncated")
  // Oversized non-event metadata must preserve the previous retryable snapshot.
  let previous=snapshot
  do { try longJob.record(String(repeating:"y",count:300_000));check(false,"oversized metadata accepted") }
  catch { }
  let preserved=try Data(contentsOf:verbose.appendingPathComponent("job.json"))
  check(preserved==previous,"failed snapshot replaced previous saved state")
  if failures > 0 { exit(1) }
  print("Status completion transaction: snapshot/journal failures, retry, full and partial results passed")
 }
}
'''.replace('UPDATE', update).replace('FINISH', finish)
  with tempfile.TemporaryDirectory() as tmp:
   path = pathlib.Path(tmp); (path/'Checks.swift').write_text(harness)
   subprocess.run(['swiftc', str(ROOT/'VoiceMatrix/LocalStudioJournal.swift'), str(ROOT/'VoiceMatrix/LocalStudioSnapshot.swift'), str(ROOT/'VoiceMatrix/RetainedMediaReader.swift'), str(path/'Checks.swift'), '-o', str(path/'checks')], check=True, timeout=60)
   subprocess.run([str(path/'checks')], check=True, timeout=30)
