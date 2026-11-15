import pathlib,subprocess,tempfile,shutil,json,hashlib,time
source=pathlib.Path('rvc-vctk-retrieval-pack-20261115');fixture=pathlib.Path('rvc-disk-vector-20261115/search-fixture.json').resolve()
report=[]
for name in ('centroids.f32','lists.json','vectors.f32'):
 with tempfile.TemporaryDirectory() as folder:
  root=pathlib.Path(folder);pack=root/'pack';shutil.copytree(source,pack);cache=root/'cache';cache.mkdir()
  p=pack/name
  with p.open('r+b') as f:
   f.seek(p.stat().st_size-1);v=f.read(1);f.seek(-1,1);f.write(bytes([v[0]^1]))
  t=time.monotonic();run=subprocess.run(['/tmp/rvc-pack-checks',str(pack),str(cache),str(fixture),'reject'],capture_output=True,text=True,timeout=90)
  assert run.returncode==0 and 'Tampered pack rejected' in run.stdout,(name,run.stdout,run.stderr[-1000:])
  assert not list(cache.iterdir())
  report.append(dict(file=name,exactSizeTamperRejected=True,cacheEmpty=True,seconds=time.monotonic()-t))
original=json.loads((source/'provenance.json').read_text())
for name,m in original['files'].items():
 with (source/name).open('rb') as f:assert hashlib.file_digest(f,'sha256').hexdigest()==m['sha256']
out=pathlib.Path('rvc-pack-import-evidence-20261115');out.mkdir(exist_ok=False)
(out/'tamper-results.json').write_text(json.dumps(dict(cases=report,originalPackHashesPreserved=True,physicalIPhoneVerified=False),indent=2))
print(json.dumps(report))
