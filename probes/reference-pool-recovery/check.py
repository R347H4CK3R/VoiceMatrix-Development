"""Require actual production receipts, not synthetic labels, to establish recovery."""
import hashlib,json,pathlib,sys
root=pathlib.Path(sys.argv[1]);fixture=json.loads((root/'fixture.json').read_text());report=json.loads((root/'pipeline-evidence.json').read_text())
assert report['fixtureSHA256']==fixture['sha256'] and report['resumeCompleted'] and report['priorProfilePreserved'] and report['freshStoreReloadPreservedIDs']
assert report['newSpeechWordErrorRate']<=0.1
assert report['sourceRetainedSHA256']==fixture['sha256'] and report['cancellationRetainedSource']
assert hashlib.sha256((root/'isolated-work/new-speech.wav').read_bytes()).hexdigest()==report['newSpeechSHA256']
paths=list((root/'isolated-work/Jobs').glob('*/candidate-*.json'))
rows=[json.loads(p.read_text()) for p in paths]
folders={r['id']:p.parent for r,p in zip(rows,paths,strict=True)}
assert rows and all(r['sourceSHA256']==fixture['sha256'] for r in rows)
by={}
for r in rows:by.setdefault(r['speaker'],[]).append(r)
recovered=[]
for speaker,attempts in by.items():
 attempts.sort(key=lambda r:r['events'][0]['date'])
 assert len(attempts)<=6
 assert sum(any(e['outcome']=='generating' for e in r['events']) for r in attempts)<=3
 for i,r in enumerate(attempts):
  if r['events'][-1]['outcome']!='saved':continue
  final=r['events'][-1]
  assert report['importedIDs']==[final['voiceID']],'New speech must use the only imported recovered voice'
  folder=folders[r['id']]
  assert hashlib.sha256((folder/('preview-'+r['id']+'.wav')).read_bytes()).hexdigest()==final['previewSHA256']
  clean=fixture['timeline'][-1]
  assert r['start']>=clean['start'] and r['end']<=clean['end']
  prior=attempts[:i]
  if len(prior)>=3 and all(x['events'][-1]['outcome']=='screeningRejected' for x in prior[:3]):
   for attempt in prior[:3]+[r]:
    folder=folders[attempt['id']];finalEvent=attempt['events'][-1]
    rh=hashlib.sha256((folder/('reference-'+attempt['id']+'.wav')).read_bytes()).hexdigest()
    quality=json.loads((folder/('quality-'+attempt['id']+'.json')).read_text())
    assert rh==finalEvent['referenceSHA256']==quality['sourceSHA256']
    assert quality['decision']['admitted'] is (attempt is r)
   matched=[]
   for rejected in prior[:3]:
    intervals=[j for j,t in enumerate(fixture['timeline']) if t['expectedContaminated'] and rejected['start']>=t['start'] and rejected['end']<=t['end']]
    assert len(intervals)==1,'Rejected reference not wholly inside a contaminated turn'
    matched.append(intervals[0])
   assert len(set(matched))==3,'Repeated crops of one turn do not prove three-turn recovery'
   recovered.append(dict(speaker=speaker,rejectionsBeforeSuccess=i,distinctRejectedTurns=matched,selectedStart=r['start'],selectedEnd=r['end']))
assert recovered,'No verified case of three screening rejections followed by clean-reference recovery'
(root/'recovery-proof.json').write_text(json.dumps(dict(recovered=recovered,physicalIPhoneVerified=False,controlledFixture=True,sourceCommit=report['sourceCommit']),indent=2))
print('Verified actual screened later-turn recovery:',recovered)
