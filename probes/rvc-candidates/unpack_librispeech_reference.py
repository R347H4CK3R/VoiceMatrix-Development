import pathlib,base64,hashlib,zipfile,io,json
r=pathlib.Path(__file__).parent
raw=base64.b64decode((r/'librispeech-reference.b64').read_text(),validate=True)
assert hashlib.sha256(raw).hexdigest()=='a9f34bb91eb808ab5ab58c2bff9976225b09e322672f095ba53ad15478d4c3a7'
names={a+'/'+b for a in ('6930-75918-0000','8455-210777-0028') for b in ('prepared.f32','pitch.json','manifest.json')}
out=r/'librispeech-reference-inputs'
with zipfile.ZipFile(io.BytesIO(raw)) as z:
 assert set(z.namelist())==names and len(z.infolist())==6
 assert sum(i.file_size for i in z.infolist())<2000000 and z.testzip() is None
 out.mkdir(exist_ok=False)
 for n in names:
  p=out/n;p.parent.mkdir(exist_ok=True);p.write_bytes(z.read(n))
for p in out.iterdir():
 m=json.loads((p/'manifest.json').read_text())
 for n,h in m['files'].items():assert hashlib.sha256((p/n).read_bytes()).hexdigest()==h
print('Verified reference fixtures unpacked')
