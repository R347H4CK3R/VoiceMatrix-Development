"""Recover exact licensed, previously tested reference inputs without rewriting transcripts."""
import hashlib,json,pathlib,zipfile
p=pathlib.Path('local-evidence');p.mkdir(exist_ok=True)
a=pathlib.Path('retained.zip')
assert hashlib.sha256(a.read_bytes()).hexdigest()=='1c9c3c29e36a23e7d62bc58a0afcfd8ef66c62c6bc7ba1a087114151be85758f'
job='mixed/work/Jobs/fe605440-0254-491c-8c43-03de2e1f8a2a/'
rows=[('positive','52b624aa-d91c-457a-a3c6-e2be6a6bfdb6','s1','0a933760c30e5ae4e0e843b1877c7833ec18edf3af7ed461651be3d7256a3ead'),('negative','5ffac92b-e162-4f24-8fd4-0b1b5fe826e2','s2','fd0049197b44f2ab96cf5ae077b6b8a5081435a54463d94fe2b04f2fdeda90a7')]
with zipfile.ZipFile(a) as z:
 for label,candidate,speaker,sha in rows:
  ident='local-fe605440-0254-491c-8c43-03de2e1f8a2a-'+speaker
  prefix=job+'collection-'+candidate+'/'
  root=p/label;folder=root/ident;folder.mkdir(parents=True,exist_ok=True)
  manifest=z.read(prefix+ident+'/manifest.json');meta=json.loads(manifest)
  data=z.read(prefix+ident+'/reference.wav')
  assert meta['id']==ident and meta['referenceSHA256']==sha and hashlib.sha256(data).hexdigest()==sha
  (folder/'manifest.json').write_bytes(manifest);(folder/'reference.wav').write_bytes(data)
  (root/'collection.json').write_bytes(z.read(prefix+'collection.json'))
 (p/'fixture-provenance.json').write_bytes(z.read('mixed/fixture.json'))
