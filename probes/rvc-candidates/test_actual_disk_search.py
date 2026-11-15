import pathlib,sys,json,hashlib,shutil,subprocess,time
sys.path.insert(0,str(pathlib.Path('rvc-index-reader-deps').resolve()))
import faiss,numpy as np
r=pathlib.Path('rvc-disk-vector-20261115')
assert hashlib.sha256(pathlib.Path('vctk-p226-verified.index').read_bytes()).hexdigest()=='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
index=faiss.read_index('vctk-p226-verified.index')
assert index.ntotal==45313 and index.d==768
query=np.asarray(json.loads(pathlib.Path('native-retrieval-case.json').read_text())['features'],dtype=np.float32).reshape(-1,768)
dist,ids=index.search(query,8);assert (ids>=0).all()
lists=[faiss.rev_swig_ptr(index.invlists.get_ids(i),index.invlists.list_size(i)).astype(int).tolist() for i in range(index.nlist)]
meta=dict(centroids=index.quantizer.reconstruct_n(0,index.nlist).ravel().tolist(),lists=lists,features=query.ravel().tolist(),expectedIDs=ids.tolist(),expectedDistances=dist.tolist())
(r/'search-fixture.json').write_text(json.dumps(meta))
shutil.copyfile(r/'vectors.f32',r/'search-test-input.f32')
digest=json.loads((r/'result.json').read_text())['vectorSHA256']
started=time.monotonic()
p=subprocess.run(['/tmp/rvc-disk-vectors',str(r/'search-test-input.f32'),str(r/'cache'),'45313',digest,str(r/'search-fixture.json')],capture_output=True,text=True,timeout=90)
assert p.returncode==0,(p.stdout,p.stderr)
report=dict(actualIndexVectors=45313,clusters=1161,queryRows=3,neighbors=24,exactIDsMatch=True,distanceTolerance=.001,fixtureSHA256=hashlib.sha256((r/'search-fixture.json').read_bytes()).hexdigest(),nativeTest=p.stdout.strip(),seconds=time.monotonic()-started,phoneVerified=False)
(r/'search-result.json').write_text(json.dumps(report,indent=2));print(json.dumps(report))
