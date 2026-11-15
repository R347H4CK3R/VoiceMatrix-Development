import pathlib,json,urllib.request,hashlib,subprocess,wave,sys
root=pathlib.Path(sys.argv[1]);root.mkdir(exist_ok=True)
sources=json.loads(pathlib.Path(__file__).with_name('sources.json').read_text());pcms=[]
for source in sources:
    flac=root/(source['id']+'.flac')
    if not flac.exists():
        # Cached asset URLs require fresh signed query parameters. The source
        # identity and immutable byte digest remain authoritative.
        with urllib.request.urlopen(source['rowAPI'],timeout=60) as response:row=json.load(response)['rows'][0]['row']
        assert row['id']==source['id']
        url=row['audio'][0]['src']
        assert url.startswith(source['audioAssetPath']+'?') or url==source['audioAssetPath']
        with urllib.request.urlopen(url,timeout=60) as response:data=response.read(2000001)
        assert hashlib.sha256(data).hexdigest()==source['sourceSHA256']
        with flac.open('xb') as f:f.write(data)
    assert hashlib.sha256(flac.read_bytes()).hexdigest()==source['sourceSHA256']
    wav=flac.with_suffix('.wav')
    subprocess.run(['ffmpeg','-v','error','-i',str(flac),'-ac','1','-ar','16000','-c:a','pcm_s16le',str(wav)],check=True)
    with wave.open(str(wav)) as f:pcms.append(f.readframes(f.getnframes()))
output=root/'assembledABA.wav'
if output.exists():raise RuntimeError('Prior assembled fixture preserved; use a fresh directory')
with wave.open(str(output),'wb') as f:
    f.setparams((1,2,16000,0,'NONE','none'));f.writeframes(pcms[0]+b'\0\0'*16000+pcms[1]+b'\0\0'*16000+pcms[0])
a,b=[len(p)/32000 for p in pcms]
manifest=dict(audioSHA256=hashlib.sha256(output.read_bytes()).hexdigest(),sources=sources,scope='Real speech, controlled assembly; repeated A is the same utterance',truth=[dict(speaker='A',start=0,end=a),dict(speaker='B',start=a+1,end=a+b+1),dict(speaker='A',start=a+b+2,end=2*a+b+2)])
(root/'fixture.json').write_text(json.dumps(manifest,indent=2))
