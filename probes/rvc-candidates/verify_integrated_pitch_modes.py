import pathlib,json,subprocess,tempfile,time,statistics,hashlib,sys
fixtures=pathlib.Path(sys.argv[1]);binary=pathlib.Path(sys.argv[2]);out=pathlib.Path(sys.argv[3])
assert not out.exists()
report={}
for name in ('4b70','5b55'):
 report[name]={};source=fixtures/name/'source.wav';manifest=json.loads((fixtures/name/'payload/manifest.json').read_text())
 assert hashlib.sha256(source.read_bytes()).hexdigest()==manifest['inputSHA256']
 for mode,golden in [('original','native'),('refined','sinc32')]:
  expected=json.loads((fixtures/name/golden/'pitch.json').read_text());durations=[]
  for repetition in range(3):
   with tempfile.TemporaryDirectory() as folder:
    started=time.perf_counter();subprocess.run([str(binary),str(source),folder,mode],check=True,timeout=90);durations.append(time.perf_counter()-started)
    actual=json.loads((pathlib.Path(folder)/'pitch.json').read_text())
    assert actual==expected,(name,mode,'Pitch mismatch')
    assert (pathlib.Path(folder)/'prepared.f32').read_bytes()==(fixtures/name/golden/'prepared.f32').read_bytes()
  report[name][mode]=dict(exactPitchMatch=True,exactPreparedMatch=True,outputFrames=[len(x) for x in expected],seconds=durations,medianSeconds=statistics.median(durations))
 report[name]['refinementRuntimeRatio']=report[name]['refined']['medianSeconds']/report[name]['original']['medianSeconds']
out.write_text(json.dumps(dict(cases=report,binarySHA256=hashlib.sha256(binary.read_bytes()).hexdigest(),timingEnvironment='Linux CPU; preprocessing plus pitch only, not iPhone or full inference',defaultChanged=False),indent=2))
print(json.dumps(report))
