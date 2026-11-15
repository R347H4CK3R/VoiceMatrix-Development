import pathlib,subprocess,json
r=pathlib.Path(__file__).parent
for case in ('5683-32865-0017','121-127105-0022'):
 for rate in ('0','.125'):
  p=subprocess.run([str(r/'tools/python.exe'),'-I','-B',str(r/'convert_librispeech_broader.py'),case,rate],capture_output=True,text=True)
  (r/('librispeech-'+case+'-'+rate+'.log')).write_text(p.stdout+'\n'+p.stderr)
  print(json.dumps(dict(case=case,rate=rate,returncode=p.returncode,tail=p.stdout[-1000:] if p.returncode==0 else p.stderr[-2500:])),flush=True)
  if p.returncode:raise SystemExit(p.returncode)
