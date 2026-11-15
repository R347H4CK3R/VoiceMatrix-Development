import pathlib,json,hashlib,sys,wave
root=pathlib.Path(sys.argv[1])
sources=json.loads(pathlib.Path(__file__).with_name('sources.json').read_text())
original=json.loads((root/'corpus/fixture.json').read_text())['sources']
for source,pinned in zip(sources,original,strict=True):
    assert all(source[k]==v for k,v in pinned.items())
    flac=root/'corpus'/(source['id']+'.flac')
    assert hashlib.sha256(flac.read_bytes()).hexdigest()==source['sourceSHA256']
    audio=flac.with_suffix('.wav')
    with wave.open(str(audio)) as f:
        assert f.getnchannels()==1 and f.getsampwidth()==2 and f.getframerate()==16000
        assert 8<=f.getnframes()/16000<=60
    case=root/source['id'];case.mkdir()
    (case/'transcript.txt').write_text(source['referenceText']+'\n')
    (case/'fixture.json').write_text(json.dumps(dict(source=source,audioSHA256=hashlib.sha256(audio.read_bytes()).hexdigest(),scope='Human corpus speech; previously used in component checks, not a blind holdout'),indent=2)+'\n')
