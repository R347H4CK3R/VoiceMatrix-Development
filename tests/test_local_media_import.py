"""Run the production admission expression. Container admission is not decoding proof."""
import pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class LocalMediaImportTests(unittest.TestCase):
 @unittest.skipUnless(shutil.which('swiftc'), 'Swift compiler required')
 def test_production_admits_common_audio_formats_and_rejects_unknown(self):
  source=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  expression=source[source.index('                    let ext ='):source.index('                    let destination =')]
  harness='''import Foundation
  enum LocalError: Error { case source }
  func admitted(_ source:URL) throws -> String { EXPRESSION; return ext }
  @main struct Check { static func main() throws {
   var failures=0
   for ext in ["mp4","mov","m4v","wav","m4a","aac","caf","mp3","MP3","aif","aiff","AIFF"] {
    do { let actual=try admitted(URL(fileURLWithPath:"/tmp/source."+ext)); if actual != ext.lowercased() {failures+=1} }
    catch {print("Rejected supported container: "+ext);failures+=1}
   }
   for ext in ["exe","ogg","flac","","mp3.exe"] {
    do {_=try admitted(URL(fileURLWithPath:"/tmp/source."+ext)); print("Accepted unsupported container: "+ext);failures+=1} catch {}
   }
   if failures>0 {exit(1)}
   print("Production local media admission passed")
  }}'''.replace('EXPRESSION',expression)
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'Check.swift').write_text(harness)
   policy=ROOT/'VoiceMatrix/LocalMediaImportPolicy.swift'
   args=['swiftc','-parse-as-library']+([str(policy)] if policy.exists() else [])+[str(p/'Check.swift'),'-o',str(p/'check')]
   subprocess.run(args,check=True,capture_output=True,text=True,timeout=60)
   subprocess.run([str(p/'check')],check=True,timeout=10)

 def test_picker_and_worker_share_policy_without_weakening_decoder(self):
  view=(ROOT/'VoiceMatrix/LocalVideoStudioView.swift').read_text()
  self.assertIn('LocalMediaImportPolicy.fileExtension(url)',view)
  self.assertIn('catch { selected = nil; selectionError = error.localizedDescription }',view)
  source=(ROOT/'VoiceMatrix/LocalVideoStudio.swift').read_text()
  self.assertLess(source.index('LocalMediaImportPolicy.fileExtension(source)'),source.index('FileManager.default.createFile(atPath: destination.path'))
  decoder=(ROOT/'VoiceMatrix/LocalVideoAudio.swift').read_text()
  for guard in ['tracks.count == 1','reader.status == .completed','referenceCoversInterval','referenceTimestampMatches','clipping < 0.01']:
   self.assertIn(guard,decoder)

 @unittest.skipUnless(__import__('sys').platform == 'darwin', 'AVFoundation decoding requires an Apple runner')
 def test_actual_mp3_and_aiff_decode_and_corrupt_input_preservation(self):
  if not shutil.which('ffmpeg'): self.fail('Install ffmpeg for the native media fixture test')
  harness='''import Foundation
  @main struct Check {
   static func main() async throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
    for name in ["synthetic.mp3","synthetic.aiff"] {
     let url=root.appendingPathComponent(name)
     _ = try LocalMediaImportPolicy.fileExtension(url)
     let before=try Data(contentsOf:url)
     let reference=try await LocalVideoAudio.extract(source:url,start:0.5,seconds:1)
     precondition(abs(reference.seconds-1)<=0.05)
     precondition(reference.rms>=0.0002 && reference.clippedFraction<0.01)
     precondition(reference.wave.prefix(4)==Data("RIFF".utf8))
     let after=try Data(contentsOf:url);precondition(before==after)
     print(name+": actual native extraction and source preservation passed")
    }
    let corrupt=root.appendingPathComponent("corrupt.mp3")
    let before=try Data(contentsOf:corrupt)
    do { _=try await LocalVideoAudio.extract(source:corrupt,start:0,seconds:1);fatalError("Corrupt audio admitted") } catch {}
    let after=try Data(contentsOf:corrupt);precondition(before==after)
    print("Corrupt MP3 rejected without changing source")
   }
  }'''
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d)
   for extension,codec in [('mp3','libmp3lame'),('aiff','pcm_s16be')]:
    subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','sine=frequency=440:duration=2','-ar','44100','-ac','2','-c:a',codec,str(p/('synthetic.'+extension))],check=True,timeout=30)
   (p/'corrupt.mp3').write_bytes(b'not an audio file; retain these bytes')
   (p/'Native.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(ROOT/'VoiceMatrix/LocalMediaImportPolicy.swift'),str(ROOT/'VoiceMatrix/LocalStudioEvidence.swift'),str(ROOT/'VoiceMatrix/LocalVideoAudio.swift'),str(p/'Native.swift'),'-o',str(p/'native')],check=True,timeout=60)
   subprocess.run([str(p/'native'),str(p)],check=True,timeout=30)

 def test_each_explicit_coordinator_target_includes_import_policy(self):
  import re
  project=(ROOT/'project.yml').read_text().split('targets:\n',1)[1]
  targets=list(re.finditer(r'(?m)^  ([A-Za-z0-9_-]+):\s*$',project))
  checked=[]
  for index,target in enumerate(targets):
   body=project[target.end():targets[index+1].start() if index+1<len(targets) else len(project)]
   if '- path: VoiceMatrix/LocalVideoStudio.swift' in body:
    checked.append(target.group(1))
    self.assertIn('- path: VoiceMatrix/LocalMediaImportPolicy.swift',body,target.group(1)+' omits the coordinator import policy')
  self.assertIn('LocalStudioDiagnostic',checked)
