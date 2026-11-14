"""Resume must check retained evidence, not just a catalog ID and policy marker."""
import pathlib, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ResumeReceiptTests(unittest.TestCase):
 def test_resume_validates_receipts_before_counting_saved_voice(self):
  src=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  reuse=src[src.index('                for speaker in groups {'):src.index('                    var previews =')]
  self.assertIn('current?.speakerAssets?[speaker.speaker]?.referenceSHA256 == existing.referenceSHA256', reuse)
  self.assertIn('validatedSpeakerAssetURL(speaker.speaker, preview: true) != nil', reuse)
 def test_busy_processing_uses_same_validator_as_playback(self):
  src=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  public=src[src.index('    func speakerAssetURL('):src.index('    private func validatedSpeakerAssetURL(')]
  self.assertIn('guard !busy else { return nil }',public)
  self.assertIn('return validatedSpeakerAssetURL(speaker, preview: preview)',public)
  internal=src[src.index('    private func validatedSpeakerAssetURL('):src.index('    private func recordSpeakerAssets(')]
  self.assertNotIn('!busy',internal)
  self.assertIn('Self.hash(bytes) == expected',internal)
  self.assertIn('values.isSymbolicLink != true',internal)
  self.assertIn('current?.speakerVoiceIDs?[speaker] == assets.voiceID',internal)

 def test_production_validator_rejects_missing_changed_and_mispaired_audio(self):
  import shutil, subprocess, tempfile
  if not shutil.which('swiftc'): self.skipTest('Swift compiler required')
  src=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  methods=src[src.index('    func speakerAssetURL('):src.index('    private func recordSpeakerAssets(')]
  harness='''import Foundation
final class Harness {
 struct Assets { var voiceID="voice"; var referenceFile="reference-one.wav"; var previewFile="preview-one.wav"; var referenceSHA256=String(repeating:"a",count:64); var previewSHA256=String(repeating:"b",count:64) }
 struct Job { var speakerAssets:[String:Assets]?=["one":Assets()]; var speakerVoiceIDs:[String:String]?=["one":"voice"] }
 enum LocalError: Error { case preview }
 var current:Job?=Job(); var busy=true; var notice=""; let folder:URL
 init(_ folder:URL) {self.folder=folder}
 // Deterministic hash boundary only. Production CryptoKit is not tested by this harness.
 static func hash(_ bytes:Data)->String {String(repeating:bytes.first == 1 ? "a":"b",count:64)}
 METHODS
 func validate()->Bool {validatedSpeakerAssetURL("one",preview:true) != nil}
}
@main struct Check {
 static func main() throws {
 let fm=FileManager.default; let root=fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
 try fm.createDirectory(at:root,withIntermediateDirectories:true)
 defer {try? fm.removeItem(at:root)}
 let h=Harness(root); let reference=root.appendingPathComponent("reference-one.wav"); let preview=root.appendingPathComponent("preview-one.wav")
 try Data(repeating:1,count:64).write(to:reference); try Data(repeating:2,count:64).write(to:preview)
 precondition(h.validate()); precondition(h.speakerAssetURL("one",preview:true) == nil)
 h.busy=false; precondition(h.speakerAssetURL("one",preview:true) != nil)
 try fm.removeItem(at:preview); precondition(!h.validate())
 try Data(repeating:1,count:64).write(to:preview); precondition(!h.validate())
 try fm.removeItem(at:preview); try fm.createSymbolicLink(at:preview,withDestinationURL:reference); precondition(!h.validate())
 try fm.removeItem(at:preview); try Data(repeating:2,count:64).write(to:preview)
 h.current?.speakerAssets?["one"]?.voiceID="wrong"; precondition(!h.validate())
 h.current?.speakerAssets?["one"]?.voiceID="voice"
 h.current?.speakerAssets?["one"]?.previewFile="preview-other.wav"; precondition(!h.validate())
 h.current?.speakerAssets?["one"]?.previewFile="preview-one.wav"
 precondition(h.validate()); print("Receipt validation: intact, busy, missing, changed, symlink, wrong voice/pair and repair passed")
 }
}
'''.replace('METHODS',methods)
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp); (p/'Test.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(p/'Test.swift'),'-o',str(p/'check')],check=True,timeout=60)
   subprocess.run([str(p/'check')],check=True,timeout=30)
