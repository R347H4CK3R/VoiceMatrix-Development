"""Predeclared synthetic mixing of pinned complete licensed human recordings."""
import array,hashlib,json,pathlib,subprocess,sys,wave
ROOT=pathlib.Path(__file__).resolve().parents[2]
def read_pcm(path):
 with wave.open(str(path)) as w:
  assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,16000)
  frames=w.getnframes();a=array.array('h',w.readframes(frames))
  if len(a)!=frames:raise ValueError('Truncated PCM source')
  if sys.byteorder!='little':a.byteswap()
  return a

def mix(a,b,start_b,gain_b=.5):
 assert start_b>=0 and gain_b in (0,.125,.5)
 n=max(len(a),start_b+len(b)) if gain_b else len(a)
 out=array.array('h');parts=[array.array('h',[0])*n,array.array('h',[0])*n]
 for i,v in enumerate(a):parts[0][i]=int(v*.5)
 if gain_b:
  for i,v in enumerate(b):parts[1][start_b+i]=int(v*gain_b)
 for x,y in zip(*parts):
  v=x+y
  if not -32768<=v<=32767:raise ValueError('Mix clipping')
  out.append(v)
 return out,parts

def write_pcm(path,pcm):
 if path.exists():raise FileExistsError(path)
 data=array.array('h',pcm)
 if sys.byteorder!='little':data.byteswap()
 with wave.open(str(path),'wb') as w:w.setparams((1,2,16000,0,'NONE','none'));w.writeframes(data.tobytes())
 return hashlib.sha256(path.read_bytes()).hexdigest()

def main(out):
 out=pathlib.Path(out);out.mkdir(parents=True,exist_ok=False)
 sources=json.loads((ROOT/'probes/coreml-real-speakers/sources.json').read_text());pcms=[];attempts=[]
 for s in sources:
  logs=[];attempts.append({'id':s['id'],'requests':logs})
  raw=(ROOT/'tests/fixtures/licensed-human-source'/(s['id']+'.flac')).read_bytes()
  assert len(raw)<=2000000 and hashlib.sha256(raw).hexdigest()==s['sourceSHA256']
  logs.append({'source':'repository-pinned-fixture','sha256':s['sourceSHA256'],'bytes':len(raw)})
  flac=out/(s['id']+'.flac');flac.write_bytes(raw);wav=flac.with_suffix('.wav')
  subprocess.run(['ffmpeg','-v','error','-nostdin','-i',str(flac),'-ac','1','-ar','16000','-c:a','pcm_s16le',str(wav)],check=True);pcms.append(read_pcm(wav))
 a,b=pcms;cases=[]
 if min(len(a),len(b))<48000:raise ValueError('Predeclared clips must both exceed 3seconds')
 for name,start,gain in [('sequential',len(a)+16000,.5),('partial-2s',max(0,len(a)-32000),.5),('full-equal',0,.5),('full-quieter',0,.125),('single-A',0,0)]:
  pcm,parts=mix(a,b,start,gain);filename=name+'.wav';sha=write_pcm(out/filename,pcm)
  tracks=[]
  for label,part in zip(['A','B'],parts):
   file=name+'-'+label+'.wav';tracks.append({'speaker':label,'file':file,'sha256':write_pcm(out/file,part)})
  cases.append({'id':name,'file':filename,'sha256':sha,'frames':len(pcm),'sampleRate':16000,'sourceIntervalOverlapFrames':max(0,min(len(a),start+len(b))-start) if gain else 0,'tracks':tracks,'placements':[{'speaker':'A','startFrame':0,'frames':len(a),'gain':.5},{'speaker':'B','startFrame':start,'frames':len(b) if gain else 0,'gain':gain}]})
 assert next(c for c in cases if c['id']=='partial-2s')['sourceIntervalOverlapFrames']==32000
 (out/'manifest.json').write_text(json.dumps({'schemaVersion':1,'sources':sources,'cases':cases,'acquisitionAttempts':attempts,'scope':'Controlled synthetic mixtures of two complete licensed utterances. Not real conversational overlap, music separation, identity, likeness or device proof.'},indent=2)+'\n')
if __name__=='__main__':main(sys.argv[1])
