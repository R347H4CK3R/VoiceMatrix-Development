import pathlib,urllib.request,json,hashlib,subprocess,sys,zipfile,wave
import numpy as np
source=pathlib.Path(sys.argv[1]).resolve();native=pathlib.Path(sys.argv[2]).resolve();sys.path.insert(0,str(source))
from tools.rvc_chunking import plan,window
out=pathlib.Path(sys.argv[3]).resolve();out.mkdir(exist_ok=False)
rows=[]
for offset in (2000,):
 api=f'https://datasets-server.huggingface.co/rows?dataset=openslr/librispeech_asr&config=clean&split=test&offset={offset}&length=1'
 d=json.load(urllib.request.urlopen(api,timeout=30));assert len(d['rows'])==1
 row=d['rows'][0]['row'];name=row['id'];assert name.replace('-','').isdigit()
 folder=out/name;folder.mkdir();url=row['audio'][0]['src'];revision=url.split('/--/')[1]
 raw=urllib.request.urlopen(url,timeout=60).read(4000001);assert 0<len(raw)<=4000000
 assert revision=='71cacbfb7e2354c4226d01e70d77d5fca3d04ba1' and name=='1580-141083-0051'
 assert hashlib.sha256(raw).hexdigest()=='3f7d90044d1a1ec56c95e9f0ec7a5bd1f1914259b6441148ea2991a341950b77'
 (folder/'source.flac').write_bytes(raw)
 subprocess.run(['/usr/bin/ffmpeg','-v','error','-i',str(folder/'source.flac'),'-map_metadata','-1','-ac','1','-ar','16000','-c:a','pcm_s16le',str(folder/'source.wav')],check=True,timeout=30)
 with wave.open(str(folder/'source.wav')) as f:
  samples=f.getnframes();assert f.getframerate()==16000 and f.getnchannels()==1 and f.getsampwidth()==2
  pcm=f.readframes(samples)
 assert 16000<=samples<=480000
 payload=folder/'payload';payload.mkdir()
 subprocess.run([str(native),str(folder/'source.wav'),str(payload),'original'],check=True,timeout=90)
 signal=np.frombuffer((payload/'prepared.f32').read_bytes(),dtype='<f4');assert len(signal)==samples
 m=dict(dataset='openslr/librispeech_asr',datasetRevision=revision,config='clean',split='test',row=offset,id=name,speakerID=row['speaker_id'],chapterID=row['chapter_id'],referenceText=row['text'],license='CC-BY-4.0',sourcePage='https://www.openslr.org/12',rowAPI=api,audioAssetPath=url.split('?')[0],sourceSHA256=hashlib.sha256(raw).hexdigest(),pcmSHA256=hashlib.sha256(pcm).hexdigest(),input16kSamples=samples,inputSeconds=samples/16000,selection='Row 2000 chosen before any conversion or ASR scoring; rates 0 and 0.125 preselected',files={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in payload.iterdir()},windowSHA256=[hashlib.sha256(window(len(signal),c.input_start,lambda ids:signal[ids]).tobytes()).hexdigest() for c in plan(len(signal))],nativeBinarySHA256=hashlib.sha256(native.read_bytes()).hexdigest())
 (payload/'manifest.json').write_text(json.dumps(m,indent=2));rows.append(m)
 print(json.dumps({k:m[k] for k in ('id','speakerID','referenceText','inputSeconds','sourceSHA256','datasetRevision')}),flush=True)
assert len(rows)==1 and rows[0]['datasetRevision']=='71cacbfb7e2354c4226d01e70d77d5fca3d04ba1'
(out/'selection.json').write_text(json.dumps(rows,indent=2))
with zipfile.ZipFile(out/'payloads.zip','x',zipfile.ZIP_DEFLATED) as z:
 for m in rows:
  for p in (out/m['id']/'payload').iterdir():z.write(p,m['id']+'/'+p.name)
print(json.dumps(dict(bytes=(out/'payloads.zip').stat().st_size,sha256=hashlib.sha256((out/'payloads.zip').read_bytes()).hexdigest())))
