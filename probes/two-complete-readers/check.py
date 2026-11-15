"""Require two distinct retained references and fresh word-checked speech for each."""
import pathlib,json,hashlib,sys,math,re

def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def verify(root,fixture,report):
 root=pathlib.Path(root);source=fixture['audioSHA256'];assert report['fixtureSHA256']==report['sourceRetainedSHA256']==source==digest(root/'complete-source.wav')
 assert all(report[k] is True for k in ['resumeCompleted','cancellationRetainedSource','freshStoreReloadPreservedIDs','priorProfilePreserved'])
 ids=report['importedIDs'];assert len(ids)==len(set(ids))==2
 speech=report['newSpeeches'];assert len(speech)==2 and {x['voiceID'] for x in speech}==set(ids)
 jobs=list((root/'work/Jobs').iterdir());assert len(jobs)==1;folder=jobs[0];assert digest(folder/'source.wav')==source
 saved={}
 for p in folder.glob('candidate-*.json'):
  c=json.loads(p.read_text());assert c['sourceSHA256']==source
  for event in c['events']:
   if event['outcome']=='saved':
    id=event['voiceID'];assert id not in saved;saved[id]=(c,event)
 assert set(saved)==set(ids);seen=set()
 for result in speech:
  c,event=saved[result['voiceID']];assert all(math.isfinite(c[k]) for k in ['start','end']) and c['start']<c['end']
  intervals=[i for i,t in enumerate(fixture['timeline']) if t['start']<=c['start']<c['end']<=t['end']];assert len(intervals)==1 and intervals[0] not in seen;seen.add(intervals[0])
  assert digest(folder/f"reference-{c['id']}.wav")==event['referenceSHA256']==result['referenceSHA256']
  assert digest(folder/f"preview-{c['id']}.wav")==event['previewSHA256']
  for key in ['file','asrFile']:assert pathlib.PurePath(result[key]).name==result[key] and result[key] not in ('','.','..')
  actual=digest(root/'work'/result['file']);assert actual==result['newSpeechSHA256']==json.loads((root/'work'/result['asrFile']).read_text())['inputSHA256']
  assert hashlib.sha256(result['transcript'].encode()).hexdigest()==json.loads((root/'work'/result['asrFile']).read_text())['transcriptSHA256']
  assert re.findall('[a-z0-9]+',result['transcript'].lower())==['please','close','the','window','and','bring','the','notebook']
  assert math.isfinite(result['newSpeechWordErrorRate']) and 0<=result['newSpeechWordErrorRate']<=.1
 assert seen=={0,1}
 return dict(twoDistinctSourceIntervals=True,allImportedProfilesGenerated=True,retainedSources=True,scope='Controlled sequential known-reader composition only; no identity, overlap, likeness or device verification')
if __name__=='__main__':
 root=pathlib.Path(sys.argv[1]);proof=verify(root,json.loads((root/'fixture.json').read_text()),json.loads((root/'pipeline-evidence.json').read_text()));(root/'independent-two-speaker-check.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps(proof))
