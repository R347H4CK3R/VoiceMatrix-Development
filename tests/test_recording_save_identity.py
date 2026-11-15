import pathlib,shutil,subprocess,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RecordingIdentityTests(unittest.TestCase):
 def test_distinct_catalog_attempts_do_not_alias_legacy_basenames(self):
  source=(ROOT/'VoiceMatrix/AudioStore.swift').read_text()
  self.assertIn('enum RecordingSaveIdentity {',source)
  helper=source[source.index('enum RecordingSaveIdentity {'):source.index('@MainActor')]
  swift=shutil.which('swiftc')
  if not swift:self.skipTest('Swift unavailable')
  with tempfile.TemporaryDirectory() as d:
   p=pathlib.Path(d);s=p/'main.swift'
   s.write_text('import Foundation\n'+helper+'''
let a=URL(fileURLWithPath:"/test/CatalogSpeechChecks/11111111-1111-1111-1111-111111111111/speech.wav")
let b=URL(fileURLWithPath:"/test/CatalogSpeechChecks/22222222-2222-2222-2222-222222222222/speech.wav")
let x=RecordingSaveIdentity.forSource(a),y=RecordingSaveIdentity.forSource(b)
precondition(x.key != y.key && x.filename != y.filename)
precondition(x.key != "speech.wav" && y.key != "speech.wav")
precondition(RecordingSaveIdentity.forSource(a).key == x.key)
let old=RecordingSaveIdentity.forSource(URL(fileURLWithPath:"/tmp/speech.wav"))
precondition(old.key == "speech.wav" && old.filename == "speech.wav")
let raw=RecordingSaveIdentity.forSource(a.deletingLastPathComponent().appendingPathComponent("speech.raw.wav"))
precondition(raw.key != x.key && raw.filename != x.filename)
''')
   subprocess.run([swift,str(s),'-o',str(p/'test')],check=True);subprocess.run([str(p/'test')],check=True)
 def test_save_and_lookup_share_identity(self):
  s=(ROOT/'VoiceMatrix/AudioStore.swift').read_text()
  self.assertEqual(s.count('let identity = RecordingSaveIdentity.forSource(url)'),2)
  self.assertIn('savedSources[identity.key] = identity.filename',s)
