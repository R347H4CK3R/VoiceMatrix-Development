import pathlib,urllib.request,hashlib,json,sys
r=pathlib.Path(__file__).parent;p=r/'candidate-vctk-p226'/'Mp226.index'
url='https://huggingface.co/Nekochu/RVC-VCTK_Voice-sample/resolve/005c2f948ee9dafd7e3aa7f261b4c3a24beebeef/M/p226/added_IVF1161_Flat_nprobe_1_Mp226_v2.index'
h=hashlib.sha256();total=0
with urllib.request.urlopen(url,timeout=60) as source,p.open('xb') as dest:
 while True:
  b=source.read(1024*1024)
  if not b:break
  total+=len(b);assert total<=143140059
  h.update(b);dest.write(b)
assert total==143140059 and h.hexdigest()=='7f556465f2e5a2ba67c05eb0a03b6b3b2a64f91218fd221a44ab8b8b801e7d50'
sys.path.insert(0,str(r/'deps-long'))
import faiss,numpy as np
faiss.omp_set_num_threads(2)
idx=faiss.read_index(str(p))
assert idx.d==768 and 8<=idx.ntotal<=50000 and idx.metric_type==faiss.METRIC_L2 and idx.is_trained
report=dict(url=url,bytes=total,sha256=h.hexdigest(),dimensions=idx.d,vectors=idx.ntotal,indexType=type(idx).__name__,nprobe=idx.nprobe,declaredLicense='Apache-2.0',productionNativeCap=20000,productionAdmitted=False)
(p.parent/'retrieval-provenance.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
