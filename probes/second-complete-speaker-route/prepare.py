"""Recover complete hash-pinned licensed source, with no crop or injected speaker identity."""
import pathlib,json,hashlib,urllib.request,subprocess,sys,wave
root=pathlib.Path(sys.argv[1]);root.mkdir(exist_ok=True)
src=json.loads(pathlib.Path('probes/human-local-studio/sources.json').read_text())[1]
assert src['id']=='4507-16021-0031'
with urllib.request.urlopen(src['rowAPI'],timeout=45) as r:row=json.load(r)['rows'][0]['row']
assert row['id']==src['id'];url=row['audio'][0]['src'];assert url.split('?')[0]==src['audioAssetPath']
with urllib.request.urlopen(url,timeout=45) as r:raw=r.read(10000001)
assert len(raw)<=10000000 and hashlib.sha256(raw).hexdigest()==src['sourceSHA256']
flac=root/'complete-source.flac';flac.write_bytes(raw)
subprocess.run(['ffmpeg','-v','error','-i',str(flac),'-ac','1','-ar','16000','-c:a','pcm_s16le',str(root/'complete-source.wav')],check=True)
with wave.open(str(root/'complete-source.wav')) as w:
 assert w.getnchannels()==1 and w.getsampwidth()==2 and w.getframerate()==16000
 duration=w.getnframes()/16000;assert 8<=duration<=60
(root/'transcript.txt').write_text(src['referenceText']+'\n')
(root/'fixture.json').write_text(json.dumps(dict(source=src,duration=duration,audioSHA256=hashlib.sha256((root/'complete-source.wav').read_bytes()).hexdigest(),scope='Second complete licensed reader, no cropped recovery mixture; previously used in grouping tests, not blind holdout'),indent=2))
