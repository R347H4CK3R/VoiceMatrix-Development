"""Fail closed unless every case contains a valid numeric observation."""
import json,math,pathlib,sys
PREFIX='VOICEMATRIX_PRECLAMP_DIAGNOSTIC '
def parse(text):
 rows=[line.split(PREFIX,1)[1] for line in text.splitlines() if PREFIX in line]
 if len(rows)!=1:raise ValueError('Expected exactly one preclamp observation')
 r=json.loads(rows[0]);a=r['preClampExpectedCounts'];b=r['postClampCounts']
 if type(r['clusterCount']) is not int or not 1<=r['clusterCount']<=32:raise ValueError('Invalid cluster count')
 if type(r['modelSpeakerSlots']) is not int or not 1<=r['modelSpeakerSlots']<=32:raise ValueError('Invalid speaker slots')
 if not isinstance(a,list) or not isinstance(b,list) or len(a)!=len(b) or not 1<=len(a)<=110000:raise ValueError('Invalid frame arrays')
 if not all(type(v) in (int,float) and math.isfinite(v) and -1<=v<=r['modelSpeakerSlots']+.00001 for v in a):raise ValueError('Invalid preclamp count')
 if not all(type(v) is int and 0<=v<=min(r['clusterCount'],r['modelSpeakerSlots']) for v in b):raise ValueError('Invalid clamped count')
 if not all(v==min(max(round(w),0),r['clusterCount'],r['modelSpeakerSlots']) for w,v in zip(a,b)):raise ValueError('Observation disagrees with unchanged clamp')
 if not all(type(r[k]) in (int,float) and math.isfinite(r[k]) and r[k]>0 for k in ['sourceBound','frameDuration']):raise ValueError('Invalid timebase')
 return r
if __name__=='__main__':
 root=pathlib.Path(sys.argv[1]);manifest=json.loads((root/'manifest.json').read_text());out={}
 for c in manifest['cases']:out[c['id']]=parse((root/(c['id']+'.log')).read_text())
 assert len(out)==5
 (root/'preclamp-observations.json').write_text(json.dumps(out,indent=2)+'\n')
 print('Validated exactly one finite observation per each of five cases.')
