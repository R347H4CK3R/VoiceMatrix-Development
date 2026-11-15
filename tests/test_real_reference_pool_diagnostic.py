import hashlib,json,pathlib,subprocess,sys,tempfile,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class RecoveryProofTests(unittest.TestCase):
 def run_case(self,mutation=None):
  with tempfile.TemporaryDirectory() as t:
   p=pathlib.Path(t);job=p/'isolated-work/Jobs/one';job.mkdir(parents=True)
   fixture=dict(sha256='abc',timeline=[dict(start=i*10,end=i*10+8,expectedContaminated=True) for i in range(3)]+[dict(start=29.4,end=36.6,expectedContaminated=False)])
   report=dict(fixtureSHA256='abc',sourceRetainedSHA256='abc',cancellationRetainedSource=True,importedIDs=['voice-one'],newSpeechSHA256=hashlib.sha256(b'new speech').hexdigest(),resumeCompleted=True,priorProfilePreserved=True,freshStoreReloadPreservedIDs=True,newSpeechWordErrorRate=0,sourceCommit='test')
   rows=[dict(sourceSHA256='abc',speaker='A',start=i*10,end=i*10+7,events=[dict(date=i,outcome='selected'),dict(date=i+.1,outcome='screeningRejected')]) for i in range(3)]
   rows.append(dict(sourceSHA256='abc',speaker='A',start=29.55,end=36.45,events=[dict(date=4,outcome='selected'),dict(date=4.1,outcome='generating'),dict(date=4.2,outcome='saved')]))
   for i,r in enumerate(rows):
    r['id']=str(i)
    ref=b'reference'+bytes([i]);preview=b'preview'+bytes([i])
    rh=hashlib.sha256(ref).hexdigest();ph=hashlib.sha256(preview).hexdigest()
    r['events'][-1].update(referenceSHA256=rh)
    (job/f'reference-{i}.wav').write_bytes(ref)
    quality=dict(sourceSHA256=rh,decision=dict(admitted=i==3))
    (job/f'quality-{i}.json').write_text(json.dumps(quality))
    if i==3:
     r['events'][-1].update(voiceID='voice-one',previewSHA256=ph)
     (job/f'preview-{i}.wav').write_bytes(preview)
   (p/'isolated-work/new-speech.wav').write_bytes(b'new speech')
   if mutation:mutation(rows,report)
   (p/'fixture.json').write_text(json.dumps(fixture));(p/'pipeline-evidence.json').write_text(json.dumps(report))
   for i,r in enumerate(rows):(job/f'candidate-{i}.json').write_text(json.dumps(r))
   return subprocess.run([sys.executable,str(ROOT/'probes/reference-pool-recovery/check.py'),str(p)],capture_output=True).returncode
 def test_exact_evidence_shape(self):self.assertEqual(self.run_case(),0)
 def test_failure_evidence_is_not_promoted(self):
  for mutate in [lambda r,p:p.update(importedIDs=['another']),lambda r,p:p.update(importedIDs=['voice-one','another']),lambda r,p:p.update(cancellationRetainedSource=False),lambda r,p:p.update(sourceRetainedSHA256='wrong'),lambda r,p:r[-1]['events'][-1].update(previewSHA256='wrong'),lambda r,p:r.pop(0),lambda r,p:r[1].update(start=0,end=7),lambda r,p:r[0].update(start=30,end=36),lambda r,p:p.update(newSpeechWordErrorRate=.5),lambda r,p:r[-1].update(start=10),lambda r,p:r[0].update(sourceSHA256='wrong'),lambda r,p:r[0]['events'][-1].update(outcome='extractionRejected')]:
   with self.subTest(mutation=mutate):self.assertNotEqual(self.run_case(mutate),0)
