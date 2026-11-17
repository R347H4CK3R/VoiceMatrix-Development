"""Execute the production Save action and source-consent policy with native Swift."""
import pathlib,subprocess,tempfile,unittest,shutil
ROOT=pathlib.Path(__file__).resolve().parents[1]
class SourceConsentTests(unittest.TestCase):
 def run_swift(self,text):
  if not shutil.which("swiftc"): self.skipTest("Swift compiler unavailable; required on native CI")
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);(p/'main.swift').write_text(text)
   subprocess.run(['swiftc',str(p/'main.swift'),'-o',str(p/'check')],check=True)
   subprocess.run([str(p/'check')],check=True)
 def test_save_action_cannot_transfer_permission_to_new_source(self):
  view=(ROOT/'VoiceMatrix/CreateReferenceVoiceView.swift').read_text()
  action=view.split('Button("Save and select voice") {',1)[1].split('}.buttonStyle',1)[0]
  helper=view[view.index('struct ReferenceVoiceConsent {'):view.index('struct CreateReferenceVoiceView:')] if 'struct ReferenceVoiceConsent {' in view else ''
  setup='var permitted=true' if not helper else 'var consent=ReferenceVoiceConsent();consent.setPermission(true,for:a)'
  # Deliberately do not deliver onChange yet. The Save action itself must refuse B.
  self.run_swift('''import Foundation
'''+helper+'''
struct Recorder {var output:URL?}
final class Library {
 var saved:URL?=nil
 func createReferenceVoice(from:URL,name:String,transcript:String,permissionConfirmed:Bool,audio:Int,studio:Int) {if permissionConfirmed {saved=from}}
}
let a=URL(fileURLWithPath:"/tmp/Imported-A.wav"),b=URL(fileURLWithPath:"/tmp/Recording-B.wav")
var recorder=Recorder(output:b)
let library=Library(),name="My voice",transcript="Exact words",audio=0,studio=0
'''+setup+'\n'+action+'''
precondition(library.saved == nil,"Permission for A was incorrectly reused for B")
''')
 def test_native_permission_tracks_import_recording_nil_and_reapproval(self):
  view=(ROOT/'VoiceMatrix/CreateReferenceVoiceView.swift').read_text()
  helper=view[view.index('struct ReferenceVoiceConsent {'):view.index('struct CreateReferenceVoiceView:')]
  action=view.split('Button("Save and select voice") {',1)[1].split('}.buttonStyle',1)[0]
  callback=view.split('.onChange(of:recorder.output) {',1)[1].split('}',1)[0].split(' in ',1)[1]
  self.run_swift('''import Foundation
'''+helper+'''
struct Recorder {var output:URL?}
final class Library {
 var saved:URL?=nil
 func createReferenceVoice(from:URL,name:String,transcript:String,permissionConfirmed:Bool,audio:Int,studio:Int) {if permissionConfirmed {saved=from}}
}
let imported=URL(fileURLWithPath:"/tmp/Imported-A.wav")
let recorded=URL(fileURLWithPath:"/tmp/Recording-B.wav")
let secondImport=URL(fileURLWithPath:"/tmp/Imported-C.wav")
var consent=ReferenceVoiceConsent(),recorder=Recorder(output:nil)
let library=Library(),audio=0,studio=0
var name="Retain name",transcript="Retain exact words"
consent.setPermission(true,for:nil)
precondition(!consent.permits(nil))
recorder.output=imported
precondition(!consent.permits(recorder.output))
consent.setPermission(true,for:imported)
precondition(consent.permits(imported))
// Failed/cancelled import does not change Recorder.output. Same-value notification
// also must not destroy the existing valid source approval.
do {let old=recorder.output,new=recorder.output
'''+callback+'''
}
precondition(consent.permits(imported))
'''+action+'''
precondition(library.saved==imported)
for replacement in [recorded,secondImport,nil,imported] as [URL?] {
 let old=recorder.output,new=replacement
 recorder.output=new
'''+callback+'''
 precondition(!consent.permits(recorder.output))
 library.saved=nil
'''+action+'''
 precondition(library.saved==nil)
 if let replacement {
  consent.setPermission(true,for:replacement)
'''+action+'''
  precondition(library.saved==replacement)
 }
}
precondition(name=="Retain name" && transcript=="Retain exact words")
consent.setPermission(false,for:recorder.output)
precondition(!consent.permits(recorder.output))
''')
 def test_toggle_save_disabled_and_change_callback_share_source_bound_policy(self):
  view=(ROOT/'VoiceMatrix/CreateReferenceVoiceView.swift').read_text()
  self.assertNotIn('@State private var permitted',view)
  self.assertIn('get:{consent.permits(recorder.output)}',view)
  self.assertIn('set:{consent.setPermission($0,for:recorder.output)}',view)
  self.assertIn('recorder.output == nil || !consent.permits(recorder.output)',view)
  self.assertIn('.onChange(of:recorder.output)',view)
  self.assertIn('if let source=recorder.output, consent.permits(source)',view)
  callback=view.split('.onChange(of:recorder.output) {',1)[1].split('}',1)[0].split(' in ',1)[1]
  self.assertNotIn('name',callback);self.assertNotIn('transcript',callback)
  self.assertNotIn('removeItem',view)
