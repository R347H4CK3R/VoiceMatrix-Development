"""Pinned real rejected candidates plus independently labeled unsuitable controls."""
import array,hashlib,json,math,pathlib,shutil,subprocess,sys,urllib.request,wave
base=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);out.mkdir()
rows=[]
def add(path,label,expected,provenance):
 rows.append(dict(file=path.name,label=label,expected=expected,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),provenance=provenance))
def write(name,pcm):
 p=out/(name+'.wav')
 with wave.open(str(p),'wb') as w:w.setparams((1,2,24000,0,'NONE','none'));w.writeframes(array.array('h',pcm).tobytes())
 return p
def decode(path,start=0,duration=8):
 raw=subprocess.check_output(['ffmpeg','-v','error','-ss',str(start),'-i',str(path),'-t',str(duration),'-ac','1','-ar','24000','-f','s16le','-'])
 pcm=array.array('h');pcm.frombytes(raw);return pcm
for sid in ['2961-960-0003','4507-16021-0031']:
 qualities=sorted((base/sid/'isolated-work/Jobs').glob('*/quality-*.json'))
 assert len(qualities)==3
 for i,q in enumerate(qualities):
  quality=json.loads(q.read_text());ref=q.with_name(q.name.replace('quality-','reference-')).with_suffix('.wav')
  assert hashlib.sha256(ref.read_bytes()).hexdigest()==quality['sourceSHA256']
  dest=out/(sid+'-'+str(i)+'.wav');shutil.copyfile(ref,dest)
  add(dest,'human read speech',True,dict(baselineRun=43681000037,source=sid,qualityFile=q.name,license='CC-BY-4.0',sourcePage='https://www.openslr.org/12'))
sources=json.loads(pathlib.Path(__file__).with_name('sources.json').read_text())
controls={}
for item in sources:
 p=out/(item['id']+'.ogg')
 with urllib.request.urlopen(urllib.request.Request(item['url'],headers={'User-Agent':'VoiceMatrix-screening-research/1.0'}),timeout=45) as r:raw=r.read(2000001)
 assert len(raw)<=2000000 and hashlib.sha256(raw).hexdigest()==item['sha256']
 p.write_bytes(raw)
 for start in ([0] if item['id']=='piano' else [10,40,70]):
  pcm=decode(p,start);assert len(pcm)==192000
  dest=write(item['id']+'-'+str(start),pcm);add(dest,item['label'],False,dict(source=item,startSeconds=start,durationSeconds=8))
  controls[item['id']]=pcm
# Controlled mixtures use real speech and real music, with documented RMS ratios.
speech=decode(base/'corpus/2961-960-0003.wav');music=controls['piano']
def rms(p):return math.sqrt(sum(float(x)*x for x in p)/len(p))
for snr in [0,10]:
 gain=rms(speech)/rms(music)/(10**(snr/20))
 mixed=[float(s)+gain*m for s,m in zip(speech,music,strict=True)];scale=min(1,30000/max(abs(x) for x in mixed))
 p=write('speech-music-'+str(snr),[round(x*scale) for x in mixed]);add(p,'constructed speech plus piano',False,dict(speech='2961-960-0003',music='piano',speechToMusicRMSdB=snr,peakScale=scale))
for name,pcm in [('silence',[0]*192000),('tone',[round(8192*math.sin(i*2*math.pi*440/24000)) for i in range(192000)])]:
 add(write(name,pcm),'synthetic '+name,False,dict(generator='prepare.py',rate=24000))
# Brief music bursts challenge temporal dilution by the longer window.
for burst in [0.5,1.0]:
 gain=rms(speech)/rms(music)
 mixed=[float(s)+gain*m if 2*24000 <= i < (2+burst)*24000 else float(s) for i,(s,m) in enumerate(zip(speech,music,strict=True))]
 scale=min(1,30000/max(abs(x) for x in mixed))
 p=write('speech-music-burst-'+str(burst),[round(x*scale) for x in mixed]);add(p,'speech plus brief piano burst',False,dict(burstSeconds=burst,burstStart=2,speechToMusicRMSdB=0,peakScale=scale))
for item in json.loads(pathlib.Path(__file__).with_name('validation-speech.json').read_text()):
 with urllib.request.urlopen(item['rowAPI'],timeout=45) as r:row=json.load(r)['rows'][0]['row']
 assert row['id']==item['id']
 url=row['audio'][0]['src'];assert url.split('?')[0]==item['audioAssetPath']
 with urllib.request.urlopen(url,timeout=45) as r:raw=r.read(2000001)
 assert hashlib.sha256(raw).hexdigest()==item['sourceSHA256']
 flac=out/(item['id']+'.flac');flac.write_bytes(raw)
 pcm=decode(flac);assert 1*24000 <= len(pcm) <= 8*24000
 add(write(item['id']+'-validation',pcm),'additional human read speech',True,item)
(out/'manifest.json').write_text(json.dumps(rows,indent=2)+'\n')
print(f'Prepared {len(rows)} labeled cases; not a broad or blind validation set')
