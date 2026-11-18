import hashlib, importlib.util, json, pathlib, shutil, subprocess, tempfile, unittest, wave
ROOT=pathlib.Path(__file__).resolve().parents[1]
class Fixtures(unittest.TestCase):
 def test_fixed_licensed_cases_and_refusal_to_overwrite(self):
  if not shutil.which('ffmpeg'): self.skipTest('ffmpeg required')
  with tempfile.TemporaryDirectory() as tmp:
   out=pathlib.Path(tmp)/'fixtures'
   subprocess.run(['python3',str(ROOT/'probes/clip-speaker-review/prepare.py'),str(out)],check=True)
   manifest=json.loads((out/'fixture.json').read_text())
   self.assertEqual({x['name']:x['frames'] for x in manifest['cases']},{'single':128000,'two':128000,'overlap':128000,'silence':128000,'minimum':48000,'maximum':160000,'below-minimum':46400})
   for case in manifest['cases']:
    data=(out/(case['name']+'.wav')).read_bytes()
    self.assertEqual(hashlib.sha256(data).hexdigest(),case['audioSHA256'])
    with wave.open(str(out/(case['name']+'.wav'))) as f:self.assertEqual((f.getnchannels(),f.getsampwidth(),f.getframerate(),f.getnframes()),(1,2,16000,case['frames']))
   self.assertEqual(len(manifest['sources']),2)
   for source in manifest['sources']:self.assertEqual(source['license'],'CC-BY-4.0')
   before=(out/'single.wav').read_bytes()
   self.assertNotEqual(subprocess.run(['python3',str(ROOT/'probes/clip-speaker-review/prepare.py'),str(out)],capture_output=True).returncode,0)
   self.assertEqual(before,(out/'single.wav').read_bytes())
if __name__=='__main__': unittest.main()
