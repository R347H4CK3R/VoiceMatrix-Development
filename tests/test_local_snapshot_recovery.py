"""Execute the production history loader with real Foundation files on Linux/macOS."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

class SnapshotRecoveryTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
    def test_history_reopens_legacy_snapshots_and_reports_invalid_files(self):
        source = (ROOT / 'VoiceMatrix/LocalVideoStudio.swift').read_text()
        loader = source[source.index('    private func reloadHistory()'):source.index('    private func update(')]
        loader = loader.replace('private func reloadHistory()', 'func reloadHistory()')
        harness = r'''import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
final class HistoryHarness {
 struct Job: Codable {
  var id: UUID; var created: Date; var updated: Date
  var sourceFile: String?; var analysisFile: String?; var referenceFile: String?; var previewFile: String?
  var acquisitionURL: URL?
  var events: [LocalStudioJournal.Event] = []
 }
 var history: [Job] = []; var historyReadFailures = 0
 let root: URL
 init(_ root: URL) { self.root = root }
 LOADER
}
@main struct Checks {
 static func main() async throws {
  let fm=FileManager.default
  let root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false)
  defer { try? fm.removeItem(at:root) }
  func folder() throws -> URL {
   let path=root.appendingPathComponent(UUID().uuidString.lowercased())
   try fm.createDirectory(at:path,withIntermediateDirectories:false)
   return path
  }
  func job(_ path: URL, _ time: Double) -> HistoryHarness.Job {
   .init(id:UUID(uuidString:path.lastPathComponent)!,created:Date(timeIntervalSince1970:time),updated:Date(timeIntervalSince1970:time))
  }
  let current=try folder(),legacy=try folder()
  try JSONEncoder().encode(job(current,20)).write(to:current.appendingPathComponent("job.json"))
  var old=job(legacy,10)
  old.events=(0..<160).map { .init(id:UUID(),time:Date(),stage:"Step",message:String(repeating:"x",count:1900)+String($0)) }
  let original=try JSONEncoder().encode(old)
  precondition(original.count>LocalStudioSnapshot.maximumBytes && original.count<LocalStudioSnapshot.maximumRecoveryBytes)
  try original.write(to:legacy.appendingPathComponent("job.json"))
  var failures=0
  let damaged=try folder();failures += 1
  try Data("not JSON".utf8).write(to:damaged.appendingPathComponent("job.json"))
  let fifo=try folder();failures += 1
  precondition(mkfifo(fifo.appendingPathComponent("job.json").path,mode_t(0o600))==0)
  let directory=try folder();failures += 1
  try fm.createDirectory(at:directory.appendingPathComponent("job.json"),withIntermediateDirectories:false)
  let linked=try folder();failures += 1
  try fm.createSymbolicLink(at:linked.appendingPathComponent("job.json"),withDestinationURL:current.appendingPathComponent("job.json"))
  let folderLink=root.appendingPathComponent(UUID().uuidString.lowercased());failures += 1
  try fm.createSymbolicLink(at:folderLink,withDestinationURL:current)
  let oversized=try folder();failures += 1
  let large=Data(repeating:32,count:LocalStudioSnapshot.maximumRecoveryBytes+1)
  try large.write(to:oversized.appendingPathComponent("job.json"))
  let mismatch=try folder();failures += 1
  try JSONEncoder().encode(job(current,30)).write(to:mismatch.appendingPathComponent("job.json"))
  let traversal=try folder();failures += 1
  var unsafe=job(traversal,30);unsafe.sourceFile="../outside.wav"
  try JSONEncoder().encode(unsafe).write(to:traversal.appendingPathComponent("job.json"))
  _ = try folder();failures += 1 // Missing snapshot, retained directory remains.
  let h=HistoryHarness(root);h.reloadHistory()
  precondition(h.history.map(\.id)==[UUID(uuidString:current.lastPathComponent)!,old.id])
  precondition(h.historyReadFailures==failures)
  precondition(h.history.last?.events.count==160)
  let after=try Data(contentsOf:legacy.appendingPathComponent("job.json"))
  precondition(after==original)
  let largeAfter=try Data(contentsOf:oversized.appendingPathComponent("job.json"))
  precondition(largeAfter==large)
  var info=stat();precondition(lstat(fifo.appendingPathComponent("job.json").path,&info)==0 && info.st_mode & mode_t(S_IFMT)==mode_t(S_IFIFO))
  // Repair only the deliberately damaged test fixture, then verify warning reset.
  try JSONEncoder().encode(job(damaged,40)).write(to:damaged.appendingPathComponent("job.json"))
  h.reloadHistory();precondition(h.history.count==3 && h.historyReadFailures==failures-1)
  // Production reloadHistory also runs in a canceled job's cleanup path.
  let canceled=Task {
   withUnsafeCurrentTask { $0?.cancel() }
   let restored=HistoryHarness(root);restored.reloadHistory()
   return restored.history.count==3 && restored.historyReadFailures==failures-1
  }
  let restoredAfterCancel=await canceled.value
  precondition(restoredAfterCancel,"Canceled cleanup must still reopen retained jobs")
  print("Production history recovery: legacy oversized data, ordering, warning counts, corruption, links, FIFO, size and path rejection; all retained bytes preserved")
 }
}
'''.replace('LOADER', loader)
        with tempfile.TemporaryDirectory() as temporary:
            folder = pathlib.Path(temporary)
            (folder / 'Checks.swift').write_text(harness)
            sources = ['LocalStudioJournal.swift', 'RetainedMediaReader.swift', 'LocalStudioSnapshot.swift', 'LocalMediaURLPolicy.swift']
            subprocess.run(['swiftc', *(str(ROOT / 'VoiceMatrix' / p) for p in sources),
                            str(folder / 'Checks.swift'), '-o', str(folder / 'checks')], check=True, timeout=90)
            subprocess.run([str(folder / 'checks')], check=True, timeout=30)

    def test_snapshot_is_in_production_target_and_warning_is_visible(self):
        project = (ROOT / 'project.yml').read_text()
        self.assertIn('path: VoiceMatrix/LocalStudioSnapshot.swift', project)
        view = (ROOT / 'VoiceMatrix/LocalVideoStudioView.swift').read_text()
        self.assertIn('local.historyReadFailures > 0', view)
        self.assertIn('local-video-history-warning', view)
        self.assertIn('no jobs were deleted', view)
