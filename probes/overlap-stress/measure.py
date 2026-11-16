"""Measure ground-truth track contribution; never assert inferred speaker identity."""
import hashlib,json,math,pathlib,sys
from prepare import read_pcm

def measure_window(a,b,start,end,rate=16000):
 if not all(math.isfinite(v) for v in [start,end]) or not 0<=start<end<=len(a)/rate+.000001 or len(a)!=len(b):raise ValueError('Invalid crop')
 lo=round(start*rate);hi=round(end*rate);x=a[lo:hi];y=b[lo:hi]
 if not x:raise ValueError('Empty crop')
 energies=[sum(v*v for v in z) for z in (x,y)];total=sum(energies)
 return {'start':start,'end':end,'frames':len(x),'trackRMS':[math.sqrt(e/len(x)) for e in energies],'trackEnergyFractions':[e/total if total else 0 for e in energies],'bothTracksNonzeroSeconds':sum(v!=0 and w!=0 for v,w in zip(x,y))/rate,'dominantTrack':('A' if energies[0]>energies[1] else 'B') if total else None}

def main(root):
 root=pathlib.Path(root);manifest=json.loads((root/'manifest.json').read_text());reports=[]
 for c in manifest['cases']:
  src=root/c['file'];assert hashlib.sha256(src.read_bytes()).hexdigest()==c['sha256'];mixed=read_pcm(src)
  parts=[]
  for t in c['tracks']:
   p=root/t['file'];assert hashlib.sha256(p.read_bytes()).hexdigest()==t['sha256'];parts.append(read_pcm(p))
  assert len(mixed)==c['frames'] and all(len(p)==len(mixed) for p in parts)
  assert all(v==a+b for v,a,b in zip(mixed,*parts)),'Known mix no longer sums exactly'
  path=root/(c['id']+'-analysis.json');report={'case':c['id'],'sourceIntervalOverlapFrames':c['sourceIntervalOverlapFrames'],'windows':[],'status':'missing-analysis'}
  if path.exists():
   analysis=json.loads(path.read_text());report['status']='measured';report['modelGroups']=len(analysis['speakerWindows']);report['segments']=analysis['segments']
   for g in analysis['speakerWindows']:
    for w in g['windows']:report['windows'].append({'modelSpeaker':g['speaker'],**measure_window(*parts,w['start'],w['end'])})
  screen=root/(c['id']+'-analysis.screening.json')
  if screen.exists():
   rows=json.loads(screen.read_text());assert len(rows)==len(report['windows'])
   for w,r in zip(report['windows'],rows):
    assert w['modelSpeaker']==r['speaker'] and w['start']==r['start'] and w['end']==r['end']
    if r.get('referenceSHA256'):
     name=r['referenceFile'];assert pathlib.Path(name).name==name
     assert hashlib.sha256((root/name).read_bytes()).hexdigest()==r['referenceSHA256']
     if r.get('evidence'):assert r['evidence']['sourceSHA256']==r['referenceSHA256']
    w['screening']=r
   report['screeningComplete']=True
  else:report['screeningComplete']=False
  reports.append(report)
 result={'scope':'Diagnostic-only synthetic mixture, raw competing-source energy measures for diarizer candidate crops, not pipeline-accepted references. No acceptance thresholds relaxed; no speaker identity or separation claim. Full source intervals include natural silence. Nonzero-sample overlap includes low-level source noise.','cases':reports}
 (root/'measurements.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
 if any(r['status']!='measured' or not r['screeningComplete'] for r in reports):raise SystemExit('Not all cases completed; retained partial observations')
if __name__=='__main__':main(sys.argv[1])
