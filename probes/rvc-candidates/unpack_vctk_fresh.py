import pathlib,base64,hashlib,zipfile,io,json
r=pathlib.Path(__file__).parent
raw=base64.b64decode((r/'vctk-fresh-payloads.b64').read_text(),validate=True)
assert hashlib.sha256(raw).hexdigest()=='1fc260459b03461e6d96e9c3f5cd2e1a7a66d38a576ab6768473ca98478c5d40'
out=r/'vctk-fresh-inputs';out.mkdir(exist_ok=False)
with zipfile.ZipFile(io.BytesIO(raw)) as z:
 allowed={n+'/'+f for n in ('4b70','5b55') for f in ('prepared.f32','pitch.json','sinc32.json','native-result.json','manifest.json')}
 assert set(z.namelist())==allowed and sum(i.file_size for i in z.infolist())<2000000
 assert z.testzip() is None
 for info in z.infolist():
  p=out/info.filename;p.parent.mkdir(exist_ok=True);p.write_bytes(z.read(info))
for n in ('4b70','5b55'):
 m=json.loads((out/n/'manifest.json').read_text())
 for f,d in m['files'].items():assert hashlib.sha256((out/n/f).read_bytes()).hexdigest()==d
 print(json.dumps(dict(fixture=n,manifest=m)),flush=True)
