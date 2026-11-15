import pathlib,subprocess,json
r=pathlib.Path(__file__).parent
for case in ('1580-141083-0051','8455-210777-0028'):
 for rate in (('0','.125') if case=='1580-141083-0051' else ('.125',)):
  p=subprocess.run([str(r/'tools/python.exe'),'-I','-B',str(r/'convert_librispeech_lowrate.py'),case,rate],capture_output=True,text=True)
  (r/('librispeech-'+case+'-'+rate+'.log')).write_text(p.stdout+'\n'+p.stderr)
  print(json.dumps(dict(case=case,rate=rate,returncode=p.returncode,tail=p.stdout[-1200:] if p.returncode==0 else p.stderr[-2500:])),flush=True)
  if p.returncode:raise SystemExit(p.returncode)
