import pathlib,zipfile,hashlib,json,sys
p=pathlib.Path('local-evidence');archive=pathlib.Path(sys.argv[1])
assert hashlib.sha256(archive.read_bytes()).hexdigest()=='1c9c3c29e36a23e7d62bc58a0afcfd8ef66c62c6bc7ba1a087114151be85758f'
with zipfile.ZipFile(archive) as z:
 prefix='mixed/work/Jobs/fe605440-0254-491c-8c43-03de2e1f8a2a/'
 ref=z.read(prefix+'reference-5ffac92b-e162-4f24-8fd4-0b1b5fe826e2.wav')
 text=z.read(prefix+'transcript-5ffac92b-e162-4f24-8fd4-0b1b5fe826e2.txt')
 provenance=z.read('mixed/fixture.json')
assert hashlib.sha256(ref).hexdigest()=='fd0049197b44f2ab96cf5ae077b6b8a5081435a54463d94fe2b04f2fdeda90a7'
assert hashlib.sha256(text).hexdigest()=='208fc1d0f0c1ed4e43a8c3fc4800380ecabfa0ca335beba53ab5eb78b54e4ce0'
(p/'reference.wav').write_bytes(ref);(p/'reference.txt').write_bytes(text);(p/'fixture-provenance.json').write_bytes(provenance)
