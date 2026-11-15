import pathlib,sys,wave,json,hashlib
base=pathlib.Path(sys.argv[1]);root=pathlib.Path(sys.argv[2]);root.mkdir()
rows=[]
for sid in ['2961-960-0003','4507-16021-0031']:
 src=base/sid/'isolated-work/new-speech.wav'
 expected={'2961-960-0003':'4dd654ffbd4e92f7251cdade25f67597729a4b2b16d69e6bbdfedb10874a3c81','4507-16021-0031':'78009ba87df1756d93ffd376731fad71b6c03645bb9239968af7800fb8ce9fc0'}[sid]
 assert hashlib.sha256(src.read_bytes()).hexdigest()==expected
 with wave.open(str(src)) as w:
  assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==24000
  pcm=w.readframes(w.getnframes())
 for margin in [0,0.08,0.16,0.32]:
  for mode in (['none'] if margin==0 else ['tail','both']):
   zero=b'\0\0'*round(margin*24000);raw=(zero if mode=='both' else b'')+pcm+(zero if margin else b'')
   p=root/(sid+'-'+str(margin)+'-'+mode+'.wav')
   with wave.open(str(p),'wb') as w:w.setparams((1,2,24000,0,'NONE','none'));w.writeframes(raw)
   rows.append(dict(file=p.name,sourceSHA256=expected,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),marginSeconds=margin,mode=mode))
import math,random,struct
rng=random.Random(1947)
for name,samples in [('silence',[0]*72000),('tone',[round(8192*math.sin(i*2*math.pi*440/24000)) for i in range(72000)]),('noise',[rng.randint(-3000,3000) for _ in range(72000)])]:
 p=root/('control-'+name+'.wav')
 with wave.open(str(p),'wb') as w:w.setparams((1,2,24000,0,'NONE','none'));w.writeframes(struct.pack('<'+'h'*len(samples),*samples))
 rows.append(dict(file=p.name,sha256=hashlib.sha256(p.read_bytes()).hexdigest(),expectedAccepted=False,synthetic=True))
(root/'manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
