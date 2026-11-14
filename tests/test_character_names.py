"""Runs production Foundation-only user-name storage, not automatic identity inference."""
import pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CharacterNameTests(unittest.TestCase):
 @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler required')
 def test_name_storage(self):
  source=ROOT/'VoiceMatrix/CharacterNameStore.swift'
  self.assertTrue(source.exists())
  harness=r'''import Foundation
@main struct Check {
 static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let store=CharacterNameStore(root:root), hash=String(repeating:"a",count:64), other=String(repeating:"b",count:64)
  let absent=try await store.name(id:"speaker_1",referenceHash:hash);precondition(absent==nil)
  try await store.save(id:"speaker_1",referenceHash:hash,name:"  Rick Sanchez  ")
  let reboot=CharacterNameStore(root:root)
  let saved=try await reboot.name(id:"speaker_1",referenceHash:hash);precondition(saved=="Rick Sanchez")
  let changed=try await reboot.name(id:"speaker_1",referenceHash:other);precondition(changed==nil)
  for invalid in ["", "\n", "bad\nname",String(repeating:"x",count:81)] {
   do {try await store.save(id:"speaker_1",referenceHash:hash,name:invalid);fatalError("invalid name accepted")}catch {}
  }
  for id in ["../escape","a/b",""] {
   do {try await store.save(id:id,referenceHash:hash,name:"Name");fatalError("unsafe ID accepted")}catch {}
  }
  let preserved=try await store.name(id:"speaker_1",referenceHash:hash);precondition(preserved==saved)
  try await store.save(id:"speaker_1",referenceHash:hash,name:nil)
  let reset=try await reboot.name(id:"speaker_1",referenceHash:hash);precondition(reset==nil)
  let target=root.appendingPathComponent("speaker_1-"+hash+".json")
  try Data("bad json".utf8).write(to:target)
  do {_ = try await store.name(id:"speaker_1",referenceHash:hash);fatalError("damaged entry accepted")}catch {}
  do {try await store.save(id:"speaker_1",referenceHash:hash,name:"Replace damage");fatalError("damage overwritten")}catch {}
  let retained=try Data(contentsOf:target);precondition(retained==Data("bad json".utf8))
  print("Name persistence, reference binding, reset, invalid input and damage preservation passed")
 }
}
'''
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp);(p/'Check.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(source),str(p/'Check.swift'),'-o',str(p/'check')],check=True,timeout=60)
   subprocess.run([str(p/'check')],check=True,timeout=20)

 def test_ui_and_diagnostic_wiring(self):
  view=(ROOT/'VoiceMatrix/CharacterLibraryView.swift').read_text()
  self.assertIn('library.displayName(voice)',view)
  self.assertIn('library.setUserName(name, for: voice)',view)
  self.assertIn('user-assigned, not identity verification',view)
  self.assertIn('library.displayName($0), $0.name',view)
  self.assertIn('path: VoiceMatrix/CharacterNameStore.swift',(ROOT/'project.yml').read_text())

 @unittest.skipUnless(shutil.which('swiftc'),'Swift compiler required')
 def test_actual_library_name_methods(self):
  s=(ROOT/'VoiceMatrix/CharacterLibrary.swift').read_text()
  methods=s[s.index('    func userName('):s.index('    private let engine =')].replace('private func refreshUserNames','func refreshUserNames')
  harness=r'''import Foundation
struct CharacterReference {let id,name,referenceSHA256:String}
@MainActor final class Library {
 let nameStore:CharacterNameStore
 var naming=false,busy=false;var nameRefresh=UUID();var message=""
 var userNames:[String:(hash:String,name:String)]=[:]
 var profiles:[CharacterReference]=[]
 init(root:URL){nameStore=CharacterNameStore(root:root)}
 METHODS
}
@main struct Check {
 @MainActor static func main() async throws {
  let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer {try? FileManager.default.removeItem(at:root)}
  let voice=CharacterReference(id:"speaker_1",name:"Unidentified speaker 1",referenceSHA256:String(repeating:"a",count:64))
  let h=Library(root:root);h.profiles=[voice]
  await h.setUserName("Morty",for:voice);precondition(h.displayName(voice)=="Morty" && !h.naming)
  let changed=CharacterReference(id:voice.id,name:voice.name,referenceSHA256:String(repeating:"b",count:64))
  precondition(h.displayName(changed)==voice.name)
  let reopened=Library(root:root);reopened.profiles=[voice]
  await reopened.refreshUserNames();precondition(reopened.displayName(voice)=="Morty")
  await h.setUserName("\n",for:voice);precondition(h.displayName(voice)=="Morty" && !h.naming)
  h.busy=true;await h.setUserName("Busy mutation",for:voice);precondition(h.displayName(voice)=="Morty");h.busy=false
  await h.setUserName(nil,for:voice);precondition(h.displayName(voice)==voice.name)
  print("Actual library name methods: display, hash invalidation, restart, failure, busy guard and reset passed")
 }
}
'''.replace('METHODS',methods)
  with tempfile.TemporaryDirectory() as tmp:
   p=pathlib.Path(tmp);(p/'Check.swift').write_text(harness)
   subprocess.run(['swiftc','-parse-as-library',str(ROOT/'VoiceMatrix/CharacterNameStore.swift'),str(p/'Check.swift'),'-o',str(p/'check')],check=True,timeout=60)
   subprocess.run([str(p/'check')],check=True,timeout=20)
