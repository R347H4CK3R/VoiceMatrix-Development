"""Execute the production history loader with real Foundation files on Linux/macOS."""
import pathlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]

def extract_job_lineage(source):
    """Keep the production Codable fields and provenance gates; omit unrelated preview policy."""
    start = source.index("    struct StrictMatroska: Codable")
    end = source.index("        // Do not compare a new speaker/reference", start)
    return source[start:end] + "    }\n"


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
// Only media/model APIs irrelevant to the history policy are stubbed.
enum LocalMediaAcquisition {
 struct Result: Codable { let file: String; let sha256: String; let bytes: Int64 }
}
enum LocalVisualEvidence { struct Report: Codable {} }
final class HistoryHarness {
 typealias Event = LocalStudioJournal.Event
 struct Similarity: Codable {}
 struct SpeakerAssets: Codable {}
 JOB_DECLARATIONS
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
   .init(id:UUID(uuidString:path.lastPathComponent)!,created:Date(timeIntervalSince1970:time),
         updated:Date(timeIntervalSince1970:time),stage:"Received",message:"History fixture")
  }
  let current=try folder(),legacy=try folder()
  try JSONEncoder().encode(job(current,20)).write(to:current.appendingPathComponent("job.json"))
  var old=job(legacy,10)
  old.events=(0..<160).map { .init(id:UUID(),time:Date(),stage:"Step",message:String(repeating:"x",count:1900)+String($0)) }
  let original=try JSONEncoder().encode(old)
  precondition(original.count>LocalStudioSnapshot.maximumBytes && original.count<LocalStudioSnapshot.maximumRecoveryBytes)
  try original.write(to:legacy.appendingPathComponent("job.json"))
  var failures=0
  let originalSHA=String(repeating:"a",count:64),mkvSHA=String(repeating:"b",count:64)
  let derivedSHA=String(repeating:"c",count:64),clipSHA=String(repeating:"d",count:64)
  let vocalsSHA=String(repeating:"e",count:64),receiptSHA=String(repeating:"f",count:64)
  let validStrict=try folder()
  var strict=job(validStrict,5)
  strict.acquisitionURL=try LocalMediaURLPolicy.input("https://www.youtube.com/watch?v=abcdefghijk")
  strict.strictMatroska = .init(schemaVersion:1, attemptID:UUID(),
                                original:.init(file:"original.mp4",sha256:originalSHA,bytes:10),
                                mkv:.init(file:"strict-00000000-0000-4000-8000-000000000001.mkv",sha256:mkvSHA,bytes:20),
                                derived:.init(file:"strict-00000000-0000-4000-8000-000000000002.mov",sha256:derivedSHA,bytes:30))
  strict.sourceFile = strict.strictMatroska?.derived?.file
  strict.sourceSHA256 = derivedSHA
  try JSONEncoder().encode(strict).write(to:validStrict.appendingPathComponent("job.json"))
  let unboundMKV=try folder();failures += 1
  var invalidStrict=job(unboundMKV,6)
  invalidStrict.acquisitionURL=strict.acquisitionURL;invalidStrict.strictMatroska=strict.strictMatroska
  invalidStrict.sourceFile="original.mp4";invalidStrict.sourceSHA256=originalSHA
  let historyRejectsUnboundMKV=try JSONEncoder().encode(invalidStrict)
  try historyRejectsUnboundMKV.write(to:unboundMKV.appendingPathComponent("job.json"))
  guard let source = strict.strictSourceLineage else { preconditionFailure("Complete strict job must describe source lineage") }
  let clip=MatroskaClipLineage(source:source,clipID:UUID(),clipReceiptSHA256:receiptSHA,
                              clipSHA256:clipSHA,requestedStart:2,requestedSeconds:10,actualStart:2,frames:441_000)
  let validVocals=try folder()
  var separated=job(validVocals,4)
  separated.sourceFile="source.wav";separated.sourceSHA256=vocalsSHA
  separated.separatedMatroska = .init(clip:clip,vocalsSHA256:vocalsSHA)
  try JSONEncoder().encode(separated).write(to:validVocals.appendingPathComponent("job.json"))
  let rejectedVocals=try folder();failures += 1
  var invalidVocals=job(rejectedVocals,7)
  invalidVocals.sourceFile="source.wav";invalidVocals.sourceSHA256=clipSHA
  invalidVocals.separatedMatroska=separated.separatedMatroska
  let historyRejectsWrongVocalsHash=try JSONEncoder().encode(invalidVocals)
  try historyRejectsWrongVocalsHash.write(to:rejectedVocals.appendingPathComponent("job.json"))
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
  let expected=[UUID(uuidString:current.lastPathComponent)!,old.id,strict.id,separated.id]
  precondition(h.history.map(\.id)==expected)
  let mkvAfter=try Data(contentsOf:unboundMKV.appendingPathComponent("job.json"))
  let vocalsAfter=try Data(contentsOf:rejectedVocals.appendingPathComponent("job.json"))
  precondition(mkvAfter==historyRejectsUnboundMKV && vocalsAfter==historyRejectsWrongVocalsHash)
  precondition(h.historyReadFailures==failures)
  precondition(h.history.first(where: {$0.id==old.id})?.events.count==160)
  let after=try Data(contentsOf:legacy.appendingPathComponent("job.json"))
  precondition(after==original)
  let largeAfter=try Data(contentsOf:oversized.appendingPathComponent("job.json"))
  precondition(largeAfter==large)
  var info=stat();precondition(lstat(fifo.appendingPathComponent("job.json").path,&info)==0 && info.st_mode & mode_t(S_IFMT)==mode_t(S_IFIFO))
  // Repair only the deliberately damaged test fixture, then verify warning reset.
  try JSONEncoder().encode(job(damaged,40)).write(to:damaged.appendingPathComponent("job.json"))
  h.reloadHistory();precondition(h.history.count==expected.count+1 && h.historyReadFailures==failures-1)
  // Production reloadHistory also runs in a canceled job's cleanup path.
  let canceled=Task {
   withUnsafeCurrentTask { $0?.cancel() }
   let restored=HistoryHarness(root);restored.reloadHistory()
   return restored.history.count==expected.count+1 && restored.historyReadFailures==failures-1
  }
  let restoredAfterCancel=await canceled.value
  precondition(restoredAfterCancel,"Canceled cleanup must still reopen retained jobs")
  print("Production history recovery: legacy oversized data, ordering, warning counts, corruption, links, FIFO, size and path rejection; all retained bytes preserved")
 }
}
'''.replace('JOB_DECLARATIONS', extract_job_lineage(source)).replace('LOADER', loader)
        with tempfile.TemporaryDirectory() as temporary:
            folder = pathlib.Path(temporary)
            (folder / 'Checks.swift').write_text(harness)
            sources = ['LocalStudioJournal.swift', 'RetainedMediaReader.swift', 'LocalStudioSnapshot.swift', 'LocalMediaURLPolicy.swift', 'MatroskaSourceLineage.swift']
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

    def test_portable_history_fixture_executes_real_lineage_guards(self):
        extract = globals().get("extract_job_lineage")
        self.assertTrue(callable(extract), "Portable executable must use the exact production Job guards")
        source = (ROOT / "VoiceMatrix/LocalVideoStudio.swift").read_text()
        job = extract(source)
        self.assertIn("struct StrictMatroska: Codable", job)
        self.assertIn("validStrictMatroska: Bool", job)
        self.assertIn("validSeparatedMatroska: Bool", job)
        self.assertNotIn("var matchingPreviewFile:", job)
