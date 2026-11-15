import pathlib,subprocess,tempfile,shutil,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CatalogQualityTests(unittest.TestCase):
 def test_actual_swift_policy(self):
  swift=shutil.which('swiftc')
  if not swift:self.skipTest('Swift unavailable')
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);main=p/'main.swift'
   main.write_text('''import Foundation
let h=String(repeating:"a",count:64),t=String(repeating:"b",count:64)
func ok(_ actual:String,_ hash:String=h,_ transcript:String=t,_ expectedHash:String=t)->Bool { CatalogSpeechQualityPolicy.accepts(expected:"Please close the window and bring the notebook.",actual:actual,audioHash:h,evidenceAudioHash:hash,transcriptHash:transcript,evidenceTranscriptHash:expectedHash) }
precondition(ok("Please close the window and bring the notebook."))
precondition(!ok("With please close the window and bring the notebook."))
precondition(!ok("Please close the window and bring the notebook.","bad"))
precondition(!ok("Please close the window and bring the notebook.",h,t,"bad"))
precondition(!ok(""))
print("catalog policy passed")
''')
   subprocess.run([swift,str(ROOT/'VoiceMatrix/LocalStudioEvidence.swift'),str(ROOT/'VoiceMatrix/CatalogSpeechQualityPolicy.swift'),str(main),'-o',str(p/'test')],check=True)
   subprocess.run([str(p/'test')],check=True)
 def test_failclosed_promotion_and_target_membership(self):
  s=(ROOT/'VoiceMatrix/CharacterLibrary.swift').read_text();s=s[s.index('    func speak('):]
  self.assertLess(s.index('await engine.unload()'),s.index('quality.check('))
  self.assertLess(s.index('guard result.verified'),s.index('output = destination'))
  self.assertNotIn('removeItem(at: destination)',s)
  self.assertIn('pendingSpeech =',s)
  ui=(ROOT/'VoiceMatrix/CharacterLibraryView.swift').read_text();self.assertIn('Review unverified audio',ui)
  project=(ROOT/'project.yml').read_text();self.assertIn('VoiceMatrix/CatalogSpeechQualityPolicy.swift',project);self.assertIn('VoiceMatrix/CatalogSpeechQuality.swift',project)

 def test_recovery_identity_cancellation_and_explicit_delete_wiring(self):
  library=(ROOT/'VoiceMatrix/CharacterLibrary.swift').read_text()
  self.assertIn('$0.referenceSHA256 == pendingSpeech.referenceHash',library)
  self.assertIn('quality.markUnverified(destination',library)
  self.assertIn('guard !busy, let item = speechHistory.first',library)
  self.assertIn('if let file = item.audio, output == file { output = nil',library)
  ui=(ROOT/'VoiceMatrix/CharacterLibraryView.swift').read_text()
  self.assertIn('confirmationDialog("Delete this retained audio',ui)
  self.assertIn('library.pendingSpeechMatchesSelection',ui)
  quality=(ROOT/'VoiceMatrix/CatalogSpeechQuality.swift').read_text()
  self.assertIn('verified: false))',quality)
  self.assertIn('request.json',quality)
  self.assertIn('256 * 1024 * 1024',quality)
  probe=(ROOT/'probes/catalog-speech-quality/Diagnostic.swift').read_text()
  for x in ['task.cancel()', 'history.count == 5','257 * 1024 * 1024','reloaded.remove(oversizedID)','fail.wordErrorRate == 0.125']:
   self.assertIn(x,probe)

 def test_native_probe_relative_path_identity(self):
  swift=shutil.which('swiftc')
  if not swift:self.skipTest('Swift unavailable')
  source=(ROOT/'probes/catalog-speech-quality/Diagnostic.swift').read_text()
  base=next(line.strip() for line in source.splitlines() if 'let base = URL(' in line)
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);main=p/'main.swift'
   main.write_text('''import Foundation
'''+base+'''
let root=base.appendingPathComponent("history",isDirectory:true)
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
let folder=root.appendingPathComponent(UUID().uuidString,isDirectory:true)
try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:false)
let raw=folder.appendingPathComponent("speech.raw.wav")
try Data([1]).write(to:raw)
let listed=try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).first!.appendingPathComponent("speech.raw.wav")
guard raw == listed else { print("URL identity differs despite same path"); exit(1) }
''')
   subprocess.run([swift,str(main),'-o',str(p/'test')],check=True)
   subprocess.run([str(p/'test'),'unused','relative-evidence'],cwd=p,check=True)
