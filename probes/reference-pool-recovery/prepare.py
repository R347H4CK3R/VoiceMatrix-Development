"""Controlled mixture of pinned real speech/music, not natural dialogue or identity proof."""
import hashlib,io,json,pathlib,sys,wave,zipfile
archive=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=True)
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='34fa4c3ed6dacab3580374f2306542162bbd85ad3b2008e814ea8456a759f254'
names={'speech-music-0.wav':'e1c3c1dcbbafb71fae27eec2ceddda80b59ad0043d221f3d907de6a3b53171e6','2961-960-0003-0.wav':'0a933760c30e5ae4e0e843b1877c7833ec18edf3af7ed461651be3d7256a3ead'}
with zipfile.ZipFile(archive) as z:
 (out/'source-screening-manifest.json').write_bytes(z.read('manifest.json'))
 pcm={}
 for n,h in names.items():
  b=z.read(n);assert hashlib.sha256(b).hexdigest()==h
  with wave.open(io.BytesIO(b)) as w:
   assert (w.getnchannels(),w.getsampwidth(),w.getframerate())==(1,2,24000)
   pcm[n]=w.readframes(w.getnframes())
 timeline=[];combined=b''
 for i,duration in enumerate([8,7.8,7.6,7.2]):
  n='speech-music-0.wav' if i<3 else '2961-960-0003-0.wav'
  start=len(combined)/48000;piece=pcm[n][:round(duration*24000)*2];assert len(piece)==round(duration*24000)*2
  combined+=piece;timeline.append(dict(start=start,end=len(combined)/48000,file=n,expectedContaminated=i<3))
  if i<3:combined+=bytes(2*24000*2)
 path=out/'recovery.wav'
 with wave.open(str(path),'wb') as w:w.setparams((1,2,24000,0,'NONE','none'));w.writeframes(combined)
 (out/'fixture.json').write_text(json.dumps(dict(kind='Controlled concatenation of real human speech and piano mixture followed by clean speech; not natural conversation',sourceArtifact=14159735991,sourceRun=43707338570,sources=names,timeline=timeline,sha256=hashlib.sha256(path.read_bytes()).hexdigest(),physicalIPhoneVerified=False),indent=2))
 print('Prepared bounded real-audio mixture fixture:',timeline)
