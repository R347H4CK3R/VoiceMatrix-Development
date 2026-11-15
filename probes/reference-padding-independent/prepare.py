"""Two independently sourced references; unchanged PCM and documented 50ms tail copies."""
import pathlib,hashlib,json,zipfile,importlib.util,sys
ROOT=pathlib.Path(__file__).resolve().parents[2]
SAMPLES={'8455-210777-0028':'c3c63ad04717b5e147c4aacf820ad10fb595c24b2ffe5a0658de50cf2959a264','1580-141083-0051':'13819bdedd365304a101c4eb9c34baf5bd9a8f13ef3d53ffc21d0d3e0ef34df6'}
def prepare(root):
 archive=root/'prior.zip';assert hashlib.sha256(archive.read_bytes()).hexdigest()=='34fa4c3ed6dacab3580374f2306542162bbd85ad3b2008e814ea8456a759f254'
 spec=importlib.util.spec_from_file_location('tail',ROOT/'probes/reference-tail-padding/prepare.py');tail=importlib.util.module_from_spec(spec);spec.loader.exec_module(tail)
 rows=[]
 with zipfile.ZipFile(archive) as z:
  manifest=json.loads(z.read('manifest.json'))
  for sid,h in SAMPLES.items():
   item=next(i for i in manifest if i['file']==sid+'-validation.wav');raw=z.read(item['file'])
   assert item['sha256']==hashlib.sha256(raw).hexdigest()==h
   assert item['provenance']['license']=='CC-BY-4.0'
   out=root/sid;out.mkdir();(out/'reference.wav').write_bytes(raw)
   (out/'reference.txt').write_text(item['provenance']['referenceText'])
   tail.SOURCE_SHA=h;proof=tail.prepare(out)
   rows.append(dict(id=sid,referenceText=item['provenance']['referenceText'],provenance=item['provenance'],proof=proof))
 (root/'independent-references.json').write_text(json.dumps(rows,indent=2)+'\n')
 return rows
if __name__=='__main__':prepare(pathlib.Path(sys.argv[1]))
