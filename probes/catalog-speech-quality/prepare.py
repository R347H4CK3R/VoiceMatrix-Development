import pathlib,hashlib,zipfile
p=pathlib.Path('local-evidence');archive=pathlib.Path('retained.zip')
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='1c9c3c29e36a23e7d62bc58a0afcfd8ef66c62c6bc7ba1a087114151be85758f'
with zipfile.ZipFile(archive) as z:
 for name,member,expected in [
  ('passed','mixed/work/new-speech-local-fe605440-0254-491c-8c43-03de2e1f8a2a-s1.wav','4dd654ffbd4e92f7251cdade25f67597729a4b2b16d69e6bbdfedb10874a3c81'),
  ('failed','mixed/work/new-speech-local-fe605440-0254-491c-8c43-03de2e1f8a2a-s2.wav','90935eb325b6270da8e4383eb626d9d9e1822e1a5884777030ebd6dfe537fe32'),
  ('long','mixed/complete-source.wav','829ddebc0aa264e2a568eaf5867447a5e01eb98408dbfbc6f3468b3c3e8e90f6')]:
  raw=z.read(member);assert hashlib.sha256(raw).hexdigest()==expected;(p/(name+'.wav')).write_bytes(raw)
 (p/'fixture-provenance.json').write_bytes(z.read('mixed/fixture.json'))
