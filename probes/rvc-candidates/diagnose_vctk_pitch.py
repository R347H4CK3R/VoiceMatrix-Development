import pathlib,sys,os,json,hashlib
r=pathlib.Path(__file__).parent
sys.path[:0]=[str(r/'deps-long'),str(r/'source-long')]
os.environ['OMP_NUM_THREADS']='2'
import numpy as np
from tools.rvc_pitch import extract_pm
from tools.rvc_chunking import plan,window
candidate=r/'candidate-vctk-p226'
out=candidate/'pitch-diagnosis.json'
assert not out.exists()
report={}
for n in ('4b13','4b70','5b55'):
 folder=(r/'objective-heldout-inputs' if n=='4b13' else r/'vctk-fresh-inputs')/n
 manifest=json.loads((folder/'manifest.json').read_text())
 audio=np.frombuffer((folder/'prepared.f32').read_bytes(),dtype='<f4')
 methods={k:json.loads((folder/f).read_text()) for k,f in [('native','pitch.json'),('sinc32','sinc32.json')]}
 rows=[]
 for i,c in enumerate(plan(len(audio))):
  a=window(len(audio),c.input_start,lambda ids:audio[ids])
  assert hashlib.sha256(a.tobytes()).hexdigest()==manifest['windowSHA256'][i]
  ref=extract_pm(a)
  row={'chunk':i,'referenceVoiced':int((ref>0).sum()),'methods':{}}
  for method,arrays in methods.items():
   actual=np.asarray(arrays[i]);assert actual.shape==ref.shape
   both=(ref>0)&(actual>0);cents=np.abs(1200*np.log2(actual[both]/ref[both]))
   row['methods'][method]=dict(jointVoiced=int(both.sum()),voicingAgreement=float(np.mean((ref>0)==(actual>0))),medianAbsCents=float(np.median(cents)) if len(cents) else None,p95AbsCents=float(np.percentile(cents,95)) if len(cents) else None,over50CentsFraction=float(np.mean(cents>50)) if len(cents) else None)
  rows.append(row)
 report[n]=rows
out.write_text(json.dumps(dict(cases=report,reference='Pinned Parselmouth autocorrelation, not ground-truth pitch',productionDefaultsChanged=False),indent=2))
print(json.dumps(report),flush=True)
