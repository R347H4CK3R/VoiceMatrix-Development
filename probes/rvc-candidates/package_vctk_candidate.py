import pathlib,json,hashlib,zipfile
r=pathlib.Path(__file__).parent/'candidate-vctk-p226'
model=r/'synthesizer-precise.onnx'
digest=hashlib.file_digest(model.open('rb'),'sha256').hexdigest()
assert digest=='f7519d6f3c248f6eb2acabd11352e0abf91515a7e95662fdb23a5b1f1e009dcc'
m=dict(schemaVersion=1,profile='rvc-v2-922-cpu',file='synthesizer.onnx',sha256=digest,bytes=model.stat().st_size)
(r/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
out=r/'VoiceMatrix-VCTK-p226-evaluation-pack.zip'
with zipfile.ZipFile(out,'x',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 z.write(model,'VCTK-p226-evaluation/synthesizer.onnx')
 for name in ['manifest.json','MODEL-CARD.md','NOTICE.txt','LICENSE-Apache-2.0.txt','LICENSE-VCTK-CC-BY-4.0.txt','provenance.json','onnx-export.json']:
  z.write(r/name,'VCTK-p226-evaluation/'+name)
 z.writestr('README.txt','Evaluation pack only. Requires source integration after build 5; published build 5 intentionally rejects this hash. Use retrieval strength zero; the synthetic diagnostic index is incompatible. This is VCTK p226, not an existing character voice. CPU parity passed; quality is mixed, phone and listening verification are unrun. Do not label production-ready.\n')
with zipfile.ZipFile(out) as z:assert z.testzip() is None
report=dict(path=out.name,bytes=out.stat().st_size,sha256=hashlib.file_digest(out.open('rb'),'sha256').hexdigest(),manifest=m,productionQualified=False,published=False)
(r/'pack-receipt.json').write_text(json.dumps(report,indent=2));print(json.dumps(report),flush=True)
