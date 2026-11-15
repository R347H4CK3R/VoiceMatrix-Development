import pathlib,sys,hashlib,json,shutil,subprocess,time
sys.path.insert(0,str(pathlib.Path('rvc-index-reader-deps').resolve()))
import faiss,numpy as np
p=pathlib.Path('vctk-p226-verified.index')
assert hashlib.sha256(p.read_bytes()).hexdigest()=='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
index=faiss.read_index(str(p));assert index.ntotal==45313 and index.d==768
r=pathlib.Path('rvc-disk-vector-20261115');r.mkdir(exist_ok=False);h=hashlib.sha256()
with (r/'vectors.f32').open('xb') as f:
 for start in range(0,index.ntotal,256):
  a=index.reconstruct_n(start,min(256,index.ntotal-start));assert np.isfinite(a).all()
  b=a.astype('<f4').tobytes();f.write(b);h.update(b)
(r/'cache').mkdir();shutil.copyfile(r/'vectors.f32',r/'mutable-test-input.f32')
started=time.monotonic()
p=subprocess.run(['/tmp/rvc-disk-vectors',str(r/'mutable-test-input.f32'),str(r/'cache'),str(index.ntotal),h.hexdigest()],capture_output=True,text=True,timeout=90)
assert p.returncode==0,(p.stdout,p.stderr)
report=dict(indexSHA256='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50',vectorSHA256=h.hexdigest(),vectorBytes=(r/'vectors.f32').stat().st_size,vectorCount=index.ntotal,dimensions=index.d,clusters=index.nlist,faissVersion=faiss.__version__,numpyVersion=np.__version__,cacheRows=16,cacheBytes=16*768*4,streamBlockBytes=16*768*4,checkedRows=[0,15,16,index.ntotal//2,index.ntotal-1],nativeTest=p.stdout.strip(),seconds=time.monotonic()-started,phoneVerified=False,productionAdmitted=False)
(r/'result.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
