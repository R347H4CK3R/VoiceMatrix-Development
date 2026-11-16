"""Source-bound controlled overlap gate; not a general overlap/likeness claim."""
import json,pathlib,sys,hashlib
IDS={'single-A','sequential','partial-2s','full-equal','full-quieter'}
def validate_results(rows):
 assert len(rows)==5 and {r['id'] for r in rows}==IDS
 for r in rows:
  assert all(type(r[k]) is int and r[k]>=0 for k in ('candidates','retained','excluded'))
  assert r['candidates']==r['retained']+r['excluded'] and r['candidates']>0
  if r['id'] in ('single-A','sequential'):assert r['retained']==r['candidates'] and r['excluded']==0
  if r['id'] in ('full-equal','full-quieter'):assert r['excluded']>0

def verify(root):
 root=pathlib.Path(root);manifest=json.loads((root/'manifest.json').read_text());cases=manifest['cases'];assert len(cases)==5 and {c['id'] for c in cases}==IDS
 runs=json.loads((root/'execution.json').read_text());assert len(runs)==5 and {r['case'] for r in runs}==IDS and all(r.get('exitCode')==0 for r in runs)
 rows=[]
 for c in cases:
  audio=root/c['file'];assert hashlib.sha256(audio.read_bytes()).hexdigest()==c['sha256']
  a=json.loads((root/(c['id']+'-analysis.json')).read_text());e=a['rawOverlap']
  assert a['selectionPolicyVersion']==5 and e['version']==1 and e['sourceSHA256']==c['sha256'] and e['modelRevision']==a['modelRevision'] and e['duration']==a['seconds']
  summary=json.loads((root/(c['id']+'-analysis.guard.json')).read_text());assert summary['sourceSHA256']==c['sha256']
  summary['id']=c['id'];assert summary['retained']==sum(len(g['windows']) for g in a['speakerWindows'])
  rows.append(summary)
 validate_results(rows)
 (root/'guard-results.json').write_text(json.dumps(rows,indent=2)+'\n');return rows
if __name__=='__main__':print(json.dumps(verify(sys.argv[1]),indent=2))
