import hashlib,json,math,pathlib,shutil,struct,subprocess,tempfile,unittest,wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
class DirectVoiceProfileTests(unittest.TestCase):
 def test_package_roundtrip_bounds_cancellation_and_preservation(self):
  self.assertIsNotNone(shutil.which('swiftc'))
  with tempfile.TemporaryDirectory() as temporary:
   root=pathlib.Path(temporary);source=root/'input.wav'
   with wave.open(str(source),'wb') as audio:
    audio.setparams((1,2,24000,0,'NONE','not compressed'))
    audio.writeframes(b''.join(struct.pack('<h',int(4000*math.sin(i*2*math.pi*220/24000))) for i in range(24000)))
   digest=hashlib.sha256(source.read_bytes()).hexdigest()
   binary=root/'checks'
   subprocess.run(['swiftc',str(ROOT/'VoiceMatrix/F5SpeechChunks.swift'),str(ROOT/'VoiceMatrix/LocalVoiceProfilePackage.swift'),str(ROOT/'tests/native/LocalVoiceProfileChecks.swift'),'-o',str(binary)],check=True,timeout=60)
   subprocess.run([str(binary),str(root),digest],check=True,timeout=30)
   collection=json.loads((root/'package/collection.json').read_text())
   self.assertEqual(collection['schemaVersion'],1)
   entry=collection['voices'][0];folder=root/'package'/entry['folder']
   profile=json.loads((folder/'manifest.json').read_text())
   self.assertEqual(profile['id'],entry['id']);self.assertEqual(profile['kind'],'f5-reference')
   self.assertFalse(profile['trainedModel']);self.assertEqual(profile['engine'],'F5TTS_v1_Base')
   self.assertEqual(profile['referenceSHA256'],hashlib.sha256((folder/'reference.wav').read_bytes()).hexdigest())
   self.assertEqual(profile['referenceBytes'],(folder/'reference.wav').stat().st_size)
   with wave.open(str(folder/'reference.wav')) as audio:
    self.assertEqual((audio.getnchannels(),audio.getsampwidth(),audio.getframerate()),(1,2,24000))
    self.assertEqual(profile['seconds'],audio.getnframes()/audio.getframerate())

 def test_actual_library_import_preserves_prior_profiles(self):
  import os,sys
  with tempfile.TemporaryDirectory() as temporary:
   root=pathlib.Path(temporary)
   with wave.open(str(root/'input.wav'),'wb') as audio:
    audio.setparams((1,2,24000,0,'NONE','not compressed'))
    audio.writeframes(b''.join(struct.pack('<h',int(4000*math.sin(i*2*math.pi*220/24000))) for i in range(24000)))
   link=[]
   env=dict(os.environ)
   if sys.platform != 'darwin':
    # Apple uses the real system CryptoKit; only Linux needs the test bridge.
    subprocess.run(['swiftc','-emit-library','-emit-module','-module-name','CryptoKit',
     str(ROOT/'tests/native/ProfileTestCryptoKit.swift'),'-o',str(root/'libCryptoKit.so'),
     '-emit-module-path',str(root/'CryptoKit.swiftmodule')],check=True,timeout=60)
    link=['-I',str(root),'-L',str(root),'-lCryptoKit']
    env['LD_LIBRARY_PATH']=str(root)
   binary=root/'library-checks'
   subprocess.run(['swiftc',*link,
    str(ROOT/'VoiceMatrix/F5SpeechChunks.swift'),str(ROOT/'VoiceMatrix/LocalVoiceProfilePackage.swift'),str(ROOT/'VoiceMatrix/CharacterFolderStore.swift'),str(ROOT/'VoiceMatrix/MatroskaSourceLineage.swift'),
    str(ROOT/'tests/native/LocalVoiceLibraryChecks.swift'),'-o',str(binary)],check=True,timeout=60)
   subprocess.run([str(binary),str(root)],env=env,check=True,timeout=60)
   index=json.loads((root/'library/index.json').read_text())
   self.assertEqual(len(index),2)
   for identifier,revision in index.items():
    folder=root/'library'/revision
    data=(folder/'manifest.json').read_bytes();reference=(folder/'reference.wav').read_bytes()
    self.assertEqual(hashlib.sha256(data+reference).hexdigest(),revision)
    self.assertEqual(json.loads(data)['referenceSHA256'],hashlib.sha256(reference).hexdigest())
