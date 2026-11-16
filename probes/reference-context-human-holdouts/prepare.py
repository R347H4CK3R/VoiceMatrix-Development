"""Predeclared independent human ASR checks. Corpus text is evaluation only."""
import hashlib,importlib.util,json,pathlib,re,subprocess,sys,urllib.request,wave
ROOT=pathlib.Path(__file__).resolve().parents[2]
def sources():
 rows=json.loads((pathlib.Path(__file__).with_name('sources.json')).read_text())
 if [r['offset'] for r in rows]!=[100,300,1200,1700] or len({r['speaker_id'] for r in rows})!=4:raise ValueError('Changed predeclared sources')
 for r in rows:
  if not re.fullmatch(r'\d+-\d+-\d+',r['id']) or r['license']!='CC-BY-4.0' or r['datasetRevision']!='71cacbfb7e2354c4226d01e70d77d5fca3d04ba1' or not re.fullmatch('[a-f0-9]{64}',r['sourceSHA256']):raise ValueError('Invalid provenance')
 return rows

def validate_row(row,source):
 if row['id']!=source['id'] or row['speaker_id']!=source['speaker_id'] or row['text']!=source['referenceText']:raise ValueError('Corpus identity or full text changed')
 url=row['audio'][0]['src']
 if url.split('?')[0]!=source['audioAssetPath']:raise ValueError('Corpus asset/revision changed')
 return url

def validate_source(raw,source):
 if len(raw)!=source['sourceBytes'] or hashlib.sha256(raw).hexdigest()!=source['sourceSHA256']:raise ValueError('Full source checksum or size changed')

def decode_complete(flac,dest,source):
 if pathlib.Path(dest).exists():raise FileExistsError(dest)
 subprocess.run(['ffmpeg','-v','error','-nostdin','-i',str(flac),'-map','0:a:0','-ac','1','-ar','24000','-c:a','pcm_s16le',str(dest)],check=True)
 raw=pathlib.Path(dest).read_bytes()
 with wave.open(str(dest)) as w:
  # All chosen 16k sources have exact integral 24k frame counts. No time crop.
  expected=source['sourceFrames']*24000/int(source['sampleRate'])
  if (w.getnchannels(),w.getsampwidth(),w.getframerate())!=(1,2,24000) or w.getnframes()!=expected:raise ValueError('Complete decoded frame count mismatch')
 return raw

def make_cases(raw,source,out):
 out=pathlib.Path(out);filename=source['id']+'-original.wav';dest=out/filename
 with dest.open('xb') as f:f.write(raw)
 digest=hashlib.sha256(raw).hexdigest()
 return [dict(id=source['id']+'-'+mode,mode=mode,file=filename,sha256=digest,sourceSHA256=digest,bytes=len(raw),expected=source['referenceText'],corpusFLACSHA256=source['sourceSHA256']) for mode in ['baseline','reference']]

def main():
 if len(sys.argv)!=2:raise SystemExit('Usage: prepare.py OUTPUT_DIRECTORY')
 out=pathlib.Path(sys.argv[1]);out.mkdir(parents=True,exist_ok=False)
 records=sources();cases=[];attempts=[]
 manifest=dict(schemaVersion=1,sources=records,cases=cases,preparationAttempts=attempts,scope='Four predeclared complete licensed human recordings, not used to select padding. Both production methods receive the same original WAV; only reference API may add250ms internal context. Corpus words are evaluation labels, never inference prompts. No likeness/device evidence.')
 def save():(out/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
 for source in records:
  record=dict(id=source['id'],prepared=False);attempts.append(record);save()
  try:
   with urllib.request.urlopen(source['rowAPI'],timeout=45) as response:body=response.read(1000001)
   if len(body)>1000000:raise ValueError('Row metadata too large')
   row=json.loads(body)['rows'][0]['row'];url=validate_row(row,source)
   with urllib.request.urlopen(url,timeout=45) as response:raw=response.read(10000001)
   validate_source(raw,source)
   flac=out/(source['id']+'.flac');flac.write_bytes(raw)
   (out/(source['id']+'-corpus.txt')).write_text(source['referenceText']+'\n')
   decoded=decode_complete(flac,out/(source['id']+'-full.wav'),source)
   cases.extend(make_cases(decoded,source,out));record['prepared']=True
  except Exception as error:record['error']=str(error)
  save()
 if not all(r['prepared'] for r in attempts):raise SystemExit('Preparation failed; all attempts retained, no replacement clips selected')
 print('Prepared exactly8cases from4new complete human recordings; no ASR or synthesis performed')
if __name__=='__main__':main()
