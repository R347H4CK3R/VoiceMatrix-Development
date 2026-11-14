import pathlib,urllib.request,json,hashlib,sys,os
ROOT=pathlib.Path(__file__).resolve().parent
OUT=ROOT/'candidate-vctk-p226'
OUT.mkdir(exist_ok=False)
repo='Nekochu/RVC-VCTK_Voice-sample';rev='005c2f948ee9dafd7e3aa7f261b4c3a24beebeef'
files=[('M/p226/Mp226.pth',55193241,'3c4c2e8ea977d7c08793126aace4baa47028b4c1bf7cd46ae5a9c359b0216693'),('M/p226/p226.flac',54497658,'8a2b79d681c4a143cb923b2e01ca57111991a243e901b1478e7b93d0ff781b97')]
evidence=[]
for path,size,expected in files:
 url='https://huggingface.co/'+repo+'/resolve/'+rev+'/'+path
 target=OUT/pathlib.PurePosixPath(path).name
 h=hashlib.sha256();total=0
 with urllib.request.urlopen(url,timeout=60) as src,target.open('xb') as dest:
  while True:
   b=src.read(1024*1024)
   if not b:break
   total+=len(b)
   if total>size:raise ValueError('size overflow')
   h.update(b);dest.write(b)
 assert total==size and h.hexdigest()==expected
 evidence.append(dict(path=path,size=size,sha256=expected,url=url))
 print(json.dumps(dict(downloaded=path,size=size,sha256=expected)),flush=True)
card=urllib.request.urlopen('https://huggingface.co/'+repo+'/raw/'+rev+'/README.md',timeout=30).read()
(OUT/'MODEL-CARD.md').write_bytes(card)
(OUT/'provenance.json').write_text(json.dumps(dict(repository=repo,revision=rev,declaredModelLicense='Apache-2.0',declaredTrainingDataset='CSTR-Edinburgh/vctk',datasetLicense='CC-BY-4.0',datasetURL='https://huggingface.co/datasets/CSTR-Edinburgh/vctk',modelCardSHA256=hashlib.sha256(card).hexdigest(),files=evidence,productionQualified=False),indent=2))
sys.path[:0]=[str(ROOT/'deps-long'),str(ROOT/'source-long')]
import torch
assert tuple(map(int,torch.__version__.split('+')[0].split('.')[:2]))>=(2,6)
m=torch.load(OUT/'Mp226.pth',map_location='cpu',weights_only=True)
report=dict(version=m.get('version'),f0=m.get('f0'),sr=m.get('sr'),config=m.get('config'),info=m.get('info'),embeddingShape=list(m['weight']['emb_g.weight'].shape),torch=torch.__version__)
(OUT/'checkpoint-inspection.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
