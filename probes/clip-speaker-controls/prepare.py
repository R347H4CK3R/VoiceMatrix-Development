"""Prespecified diagnostic controls; original regression fixtures remain byte-identical."""
import hashlib,importlib.util,json,pathlib,subprocess,sys,wave
ROOT=pathlib.Path(__file__).resolve().parents[2]
def prepare(out):
 spec=importlib.util.spec_from_file_location('original',ROOT/'probes/clip-speaker-review/prepare.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);module.prepare(out)
 manifest=json.loads((out/'fixture.json').read_text())
 sources=json.loads((ROOT/'probes/reference-context-human-holdouts/sources.json').read_text());pcm={}
 for source in sources:
  path=ROOT/'tests/fixtures/licensed-human-holdouts'/(source['id']+'.flac');data=path.read_bytes()
  assert len(data)==source['sourceBytes'] and hashlib.sha256(data).hexdigest()==source['sourceSHA256']
  raw=subprocess.check_output(['ffmpeg','-v','error','-i',str(path),'-ac','1','-ar','16000','-f','s16le','-'])
  assert len(raw)==source['sourceFrames']*2 and len(raw)>=96000
  pcm[str(source['speaker_id'])]=raw[:96000]
 def add(name,data,truth):
  path=out/(name+'.wav')
  with wave.open(str(path),'wb') as f:f.setparams((1,2,16000,0,'NONE','none'));f.writeframes(data)
  manifest['cases'].append(dict(name=name,frames=len(data)//2,seconds=len(data)/32000,audioSHA256=hashlib.sha256(path.read_bytes()).hexdigest(),truth=truth))
 for a,b in [('1320','7729'),('4446','3729')]:
  add('pair-'+a+'-'+b,pcm[a]+bytes(32000)+pcm[b],[dict(speaker=a,start=0,end=3),dict(speaker=b,start=4,end=7)])
  add('pair-'+a+'-'+b+'-no-gap',pcm[a]+pcm[b],[dict(speaker=a,start=0,end=3),dict(speaker=b,start=3,end=6)])
 for id in ['1320','7729','4446','3729']:
  add('same-'+id,pcm[id]+bytes(32000)+pcm[id],[dict(speaker=id,start=0,end=3,repeatedControl=True),dict(speaker=id,start=4,end=7,repeatedControl=True)])
 manifest['controlSources']=sources
 manifest['controlScope']='Prespecified first3s crops, fixed pairs1320/7729 and4446/3729. Matched same-speaker control repeats identical3s across1s silence, not independent utterances. Sources previously used in ASR holdout work, not blind population evidence. Original cases unchanged; no selection based on diarization outcome.'
 (out/'fixture.json').write_text(json.dumps(manifest,indent=2))
if __name__=='__main__':prepare(pathlib.Path(sys.argv[1]))
