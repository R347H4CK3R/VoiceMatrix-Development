"""Diagnostic sequential composition, not a captured conversation or overlap test."""
import pathlib,sys,hashlib,json,zipfile,wave,io
ARCHIVE_SHA='fc0a079d1d23e9a482acf277d7b6b8f987ec906ca1add642a53ad2fe29cdc924'
SOURCES=['42d940f230a5ff5da679a6d62aa7dcfe2fc1ca40359722814dd5edc08349bcb6','dfee7acd9517d9c4ceb9c2b08ad827bbfb78698617820228a978e00dec9c9b9a']
def compose(waves):
 assert len(waves)==2
 pcm=[];timeline=[];frames=0
 for i,raw in enumerate(waves):
  with wave.open(io.BytesIO(raw)) as w:
   assert (w.getnchannels(),w.getsampwidth(),w.getframerate(),w.getcomptype())==(1,2,16000,'NONE')
   n=w.getnframes();data=w.readframes(n);assert n>0 and len(data)==n*2
  if i:pcm.append(b'\0'*64000);frames+=32000
  timeline.append(dict(start=frames/16000,end=(frames+n)/16000));pcm.append(data);frames+=n
 out=io.BytesIO()
 with wave.open(out,'wb') as w:w.setparams((1,2,16000,0,'NONE','not compressed'));w.writeframes(b''.join(pcm))
 return out.getvalue(),timeline
def main():
 archive=pathlib.Path(sys.argv[1]);root=pathlib.Path(sys.argv[2]);assert hashlib.sha256(archive.read_bytes()).hexdigest()==ARCHIVE_SHA;root.mkdir(parents=True,exist_ok=True)
 with zipfile.ZipFile(archive) as z:
  waves=[z.read(n+'/complete-source.wav') for n in ('first','second')]
  sources=[json.loads(z.read(n+'/fixture.json')) for n in ('first','second')]
  transcripts=[z.read(n+'/transcript.txt').decode().strip() for n in ('first','second')]
 assert [hashlib.sha256(w).hexdigest() for w in waves]==SOURCES
 mixed,timeline=compose(waves);assert timeline[-1]['end']<60
 for i,w in enumerate(waves):
  (root/f'original-{i}.wav').write_bytes(w);(root/f'original-{i}.txt').write_text(transcripts[i]+'\n')
 (root/'complete-source.wav').write_bytes(mixed);(root/'transcript.txt').write_text(' '.join(transcripts)+'\n')
 (root/'fixture.json').write_text(json.dumps(dict(audioSHA256=hashlib.sha256(mixed).hexdigest(),timeline=timeline,sources=sources,originalSHA256=SOURCES,archiveSHA256=ARCHIVE_SHA,scope='Synthesized sequential composition of two known complete licensed recordings with two seconds of silence. No speaker IDs injected; not blind, overlap, identity, likeness or iPhone evidence.'),indent=2)+'\n')
if __name__=='__main__':main()
