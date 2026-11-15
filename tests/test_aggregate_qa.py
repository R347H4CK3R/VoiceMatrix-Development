import hashlib,json,sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parents[1]/'tools'))
from aggregate_native_qa import combine
class AggregateQATests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.root=Path(self.tmp.name)
  self.lock=dict(revision='pinned',requiresVoiceConversionChecks=True,voices=[dict(id=n,sha256=n*64,engine='phonon31m',category='Everyday Voices') for n in ['a','b']])
  for name in ['a','b']:
   folder=self.root/name;folder.mkdir();audio=(name*80).encode();digest=hashlib.sha256(audio).hexdigest()
   base=dict(id=name,embeddingSHA256=name*64,audioSHA256=digest,audioSeconds=1.5,elapsedSeconds=1.0,nonSilentWAVDecoded=True)
   converted=dict(base,file='vc-'+name+'.wav',referenceText='Test words')
   (folder/(name+'.wav')).write_bytes(audio);(folder/converted['file']).write_bytes(audio)
   report=dict(inferenceFingerprint='f'*64,modelRevision='pinned',profiles=[base],conversionChecks=[converted],additionalEnglishChecks=[])
   (folder/'voice-synthesis-results.json').write_text(json.dumps(report))
 def tearDown(self):self.tmp.cleanup()
 def test_complete_disjoint_shards_are_combined(self):
  report=combine(self.root,self.lock,self.root/'output')
  self.assertEqual(len(report['profiles']),2);self.assertEqual(len(report['conversionChecks']),2)
 def test_missing_voice_is_rejected(self):
  (self.root/'b/voice-synthesis-results.json').unlink()
  with self.assertRaises(ValueError):combine(self.root,self.lock,self.root/'output')
 def test_tampered_audio_is_rejected(self):
  (self.root/'a/a.wav').write_bytes(b'wrong')
  with self.assertRaises(ValueError):combine(self.root,self.lock,self.root/'output')
 def test_missing_conversion_proof_is_rejected(self):
  p=self.root/'a/voice-synthesis-results.json';d=json.loads(p.read_text());d['conversionChecks']=[];p.write_text(json.dumps(d))
  with self.assertRaises(ValueError):combine(self.root,self.lock,self.root/'output')

 def test_mismatched_inference_shards_are_rejected(self):
  p=self.root/'a/voice-synthesis-results.json';d=json.loads(p.read_text());d['inferenceFingerprint']='0'*64;p.write_text(json.dumps(d))
  with self.assertRaisesRegex(ValueError,'fingerprint'):combine(self.root,self.lock,self.root/'output')
 def test_old_unbound_evidence_is_rejected(self):
  p=self.root/'a/voice-synthesis-results.json';d=json.loads(p.read_text());del d['inferenceFingerprint'];p.write_text(json.dumps(d))
  with self.assertRaisesRegex(ValueError,'fingerprint'):combine(self.root,self.lock,self.root/'output')

 def rename_profile_audio(self, shard, filename):
  path=self.root/shard/'voice-synthesis-results.json';report=json.loads(path.read_text())
  (self.root/shard/(shard+'.wav')).rename(self.root/shard/filename)
  report['profiles'][0]['file']=filename;path.write_text(json.dumps(report))
 def test_cross_shard_filename_collision_rejected_before_publication(self):
  for shard in ['a','b']:self.rename_profile_audio(shard,'shared.wav')
  output=self.root/'output'
  with self.assertRaisesRegex(ValueError,'filename collision'):combine(self.root,self.lock,output)
  self.assertFalse(list(output.glob('*.wav')))
  self.assertFalse((output/'voice-synthesis-results.json').exists())
 def test_case_and_unicode_equivalent_output_names_rejected(self):
  for names in [('Shared.wav','shared.wav'),('caf\u00e9.wav','cafe\u0301.wav')]:
   with self.subTest(names=names):
    # Restore each baseline filename before assigning the next pair.
    for shard,name in zip(['a','b'],names):
     p=self.root/shard/'voice-synthesis-results.json';d=json.loads(p.read_text())
     old=d['profiles'][0].get('file',shard+'.wav')
     (self.root/shard/old).rename(self.root/shard/name)
     d['profiles'][0]['file']=name;p.write_text(json.dumps(d))
    output=self.root/'output'
    with self.assertRaisesRegex(ValueError,'filename collision'):combine(self.root,self.lock,output)
    self.assertFalse(list(output.glob('*.wav')))
 def test_late_invalid_shard_does_not_publish_partial_audio(self):
  last=list(self.root.rglob('voice-synthesis-results.json'))[-1]
  (last.parent/(last.parent.name+'.wav')).write_bytes(b'wrong')
  output=self.root/'output'
  with self.assertRaises(ValueError):combine(self.root,self.lock,output)
  self.assertFalse(list(output.glob('*.wav')))
