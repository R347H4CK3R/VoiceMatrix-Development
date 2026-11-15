import pathlib,subprocess,json
r=pathlib.Path(__file__).parent
for case in ('2961-960-0003','4507-16021-0031'):
 for rate in ('0','.125'):
  p=subprocess.run([str(r/'tools/python.exe'),'-I','-B',str(r/'convert_librispeech_heldout_next.py'),case,rate],capture_output=True,text=True)
  (r/('librispeech-'+case+'-'+rate+'.log')).write_text(p.stdout+'\n'+p.stderr)
  print(json.dumps(dict(case=case,rate=rate,returncode=p.returncode,tail=p.stdout[-1000:] if p.returncode==0 else p.stderr[-2500:])),flush=True)
  if p.returncode:raise SystemExit(p.returncode)
p=subprocess.run([str(r/'tools/python.exe'),'-I','-B',str(r/'evaluate_librispeech_heldout_next.py')],capture_output=True,text=True)
(r/'librispeech-heldout-next-evaluation.log').write_text(p.stdout+'\n'+p.stderr)
print(json.dumps(dict(evaluationReturncode=p.returncode,tail=p.stdout[-2500:] if p.returncode==0 else p.stderr[-2500:])),flush=True)
raise SystemExit(p.returncode)
