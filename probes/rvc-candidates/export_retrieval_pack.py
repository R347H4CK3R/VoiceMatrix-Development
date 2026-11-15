import sys,pathlib,json,hashlib,shutil
sys.path.insert(0,str(pathlib.Path('rvc-index-reader-deps').resolve()))
import faiss,numpy as np
raw=pathlib.Path('vctk-p226-verified.index');assert hashlib.sha256(raw.read_bytes()).hexdigest()=='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
index=faiss.read_index(str(raw));out=pathlib.Path('rvc-vctk-retrieval-pack-20261115');out.mkdir(exist_ok=False)
(out/'centroids.f32').write_bytes(index.quantizer.reconstruct_n(0,index.nlist).astype('<f4').tobytes())
lists=[faiss.rev_swig_ptr(index.invlists.get_ids(i),index.invlists.list_size(i)).astype(int).tolist() for i in range(index.nlist)]
(out/'lists.json').write_text(json.dumps(lists,separators=(',',':')))
shutil.copyfile('rvc-disk-vector-20261115/vectors.f32',out/'vectors.f32')
meta={'schemaVersion':1,'profile':'vctk-p226-ivf1161'}
(out/'manifest.json').write_text(json.dumps(meta,separators=(',',':')))
proof={p.name:{'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in out.iterdir()}
(out/'provenance.json').write_text(json.dumps({'upstreamRevision':'005c2f948ee9dafd7e3aa7f261b4c3a24beebeef','indexSHA256':hashlib.sha256(raw.read_bytes()).hexdigest(),'files':proof,'productionQualified':False},indent=2))
print(json.dumps(proof))
