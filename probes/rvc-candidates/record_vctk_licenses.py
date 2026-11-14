import pathlib,json,urllib.request,hashlib
out=pathlib.Path(__file__).parent/'candidate-vctk-p226'
for name,url in [('LICENSE-Apache-2.0.txt','https://www.apache.org/licenses/LICENSE-2.0.txt'),('LICENSE-VCTK-CC-BY-4.0.txt','https://datashare.ed.ac.uk/server/api/core/bitstreams/956a1688-0b59-428c-8a2f-10837433dde3/content')]:
 data=urllib.request.urlopen(url,timeout=30).read(65537)
 assert 1000<len(data)<=65536
 (out/name).write_bytes(data)
 print(json.dumps(dict(file=name,sha256=hashlib.sha256(data).hexdigest(),url=url)),flush=True)
(out/'NOTICE.txt').write_text('Model: Nekochu/RVC-VCTK_Voice-sample, revision 005c2f948ee9dafd7e3aa7f261b4c3a24beebeef, M/p226/Mp226.pth. Publisher-declared Apache-2.0.\nTraining dataset: CSTR VCTK Corpus 0.92, Junichi Yamagishi, Christophe Veaux and Kirsten MacDonald (2019), University of Edinburgh CSTR, https://doi.org/10.7488/ds/2645, CC BY 4.0.\nChanges: converted checkpoint to fixed-window ONNX with explicit random tensors; phase accumulation promoted to float64 for numerical parity. No voice endorsement or identity claim. Evaluation candidate, not production-qualified.\n')
