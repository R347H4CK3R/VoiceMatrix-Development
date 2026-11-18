"""Offline deterministic crops of repository-owned CC-BY-4.0 speech; no generated voices."""
import array, hashlib, json, pathlib, subprocess, sys, wave
ROOT=pathlib.Path(__file__).resolve().parents[2]
def prepare(destination):
 destination.mkdir(parents=True,exist_ok=False)
 sources=json.loads((ROOT/'probes/coreml-real-speakers/sources.json').read_text())
 pcms=[]
 for source in sources:
  path=ROOT/'tests/fixtures/licensed-human-source'/(source['id']+'.flac')
  assert hashlib.sha256(path.read_bytes()).hexdigest()==source['sourceSHA256']
  raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-ac','1','-ar','16000','-f','s16le','-'])
  pcm=array.array('h');pcm.frombytes(raw)
  if sys.byteorder!='little':pcm.byteswap()
  assert len(pcm)>=160000, 'Fixture must contain genuine full 10 seconds; never pad/repeat speech'
  pcms.append(pcm)
 a,b=pcms
 cases=[('single',a[:128000],[dict(speaker='A',start=0,end=8,sourceOffset=0)]),
 ('two',a[:64000]+b[:64000],[dict(speaker='A',start=0,end=4,sourceOffset=0),dict(speaker='B',start=4,end=8,sourceOffset=0)]),
 ('overlap',array.array('h',(int(x/2)+int(y/2) for x,y in zip(a[:128000],b[:128000]))),[dict(speaker='A',start=0,end=8,sourceOffset=0,gain=.5),dict(speaker='B',start=0,end=8,sourceOffset=0,gain=.5)]),
 ('silence',array.array('h',[0])*128000,[]),('minimum',a[:48000],[dict(speaker='A',start=0,end=3,sourceOffset=0)]),
 ('maximum',a[:160000],[dict(speaker='A',start=0,end=10,sourceOffset=0)]),('below-minimum',a[:46400],[dict(speaker='A',start=0,end=2.9,sourceOffset=0)])]
 manifest=[]
 for name,pcm,truth in cases:
  frames=len(pcm)
  if sys.byteorder!='little':pcm.byteswap()
  path=destination/(name+'.wav')
  with wave.open(str(path),'wb') as f:f.setparams((1,2,16000,0,'NONE','none'));f.writeframes(pcm.tobytes())
  manifest.append(dict(name=name,frames=frames,seconds=frames/16000,audioSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),truth=truth))
 (destination/'fixture.json').write_text(json.dumps(dict(sources=sources,sampleRate=16000,cases=manifest,scope='Controlled fixed crops/mix of licensed real speech. Truth is construction, not a model identity claim.'),indent=2))
if __name__=='__main__':prepare(pathlib.Path(sys.argv[1]))
