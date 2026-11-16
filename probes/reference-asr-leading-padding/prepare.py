"""Diagnostic PCM context experiment, never production inference or transcript correction."""
import hashlib, io, json, math, pathlib, re, sys, wave, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[2]
ARCHIVE_SHA='1c9c3c29e36a23e7d62bc58a0afcfd8ef66c62c6bc7ba1a087114151be85758f'
PREFIX='mixed/work/Jobs/fe605440-0254-491c-8c43-03de2e1f8a2a/'
REFERENCE=PREFIX+'reference-5ffac92b-e162-4f24-8fd4-0b1b5fe826e2.wav'
TRANSCRIPT=PREFIX+'transcript-5ffac92b-e162-4f24-8fd4-0b1b5fe826e2.txt'
PINNED={REFERENCE:'fd0049197b44f2ab96cf5ae077b6b8a5081435a54463d94fe2b04f2fdeda90a7',TRANSCRIPT:'208fc1d0f0c1ed4e43a8c3fc4800380ecabfa0ca335beba53ab5eb78b54e4ce0'}
VARIANTS=[('original',0,0),('leading250',.25,0),('leading500',.5,0),('both500',.5,.5)]
HOLDOUTS={'conversion-source':('8741b5ebb943f4c39006b6c7a7dd5ca92f344edb402744ad7132ee1f94ff45b4','I found a strange device near the portal.'),'conversion-reference':('0840a3b08d2d438804e760afa54bc1c9cdf1c8b33bffdc1ab458be4ab3740cd2','Please close the window and bring the notebook.')}
def digest(raw):return hashlib.sha256(raw).hexdigest()
def read_archive(path,expected_hash,members):
 path=pathlib.Path(path)
 if path.is_symlink() or not path.is_file() or path.stat().st_size>512*1024*1024:raise ValueError('Invalid archive')
 raw=path.read_bytes()
 if digest(raw)!=expected_hash:raise ValueError('Archive checksum mismatch')
 with zipfile.ZipFile(io.BytesIO(raw)) as z:
  infos=z.infolist();names=[x.filename for x in infos]
  if len(names)!=len(set(names)):raise ValueError('Duplicate archive member')
  for i in infos:
   name=i.filename;parts=pathlib.PurePosixPath(name).parts
   if '\\' in name or name.startswith('/') or '..' in parts or ':' in name or (i.external_attr>>16)&0o170000==0o120000:raise ValueError('Unsafe archive member')
  results={}
  for name,expected in members.items():
   if name not in names or z.getinfo(name).file_size>8_388_608:raise ValueError('Missing or excessive member')
   data=z.read(name)
   if digest(data)!=expected:raise ValueError('Member checksum mismatch')
   results[name]=data
  return results

def pad(raw,leading,trailing):
 if (leading,trailing) not in [(a,b) for _,a,b in VARIANTS]:raise ValueError('Unapproved padding')
 if len(raw)>8_388_608:raise ValueError('Audio too large')
 with wave.open(io.BytesIO(raw)) as w:
  rate=w.getframerate();frames=w.getnframes()
  if w.getnchannels()!=1 or w.getsampwidth()!=2 or w.getcomptype()!='NONE' or not 16000<=rate<=48000 or not .2<=frames/rate<=29:raise ValueError('Invalid PCM')
  pcm=w.readframes(frames)
  if len(pcm)!=frames*2:raise ValueError('Truncated PCM')
 lead=round(leading*rate);tail=round(trailing*rate)
 if frames+lead+tail>30*rate:raise ValueError('Audio beyond ASR bound')
 if not lead and not tail:out=raw
 else:
  b=io.BytesIO()
  with wave.open(b,'wb') as w:w.setparams((1,2,rate,0,'NONE','none'));w.writeframes(bytes(lead*2)+pcm+bytes(tail*2))
  out=b.getvalue()
 return out,dict(sourceSHA256=digest(raw),sourceBytes=len(raw),sourceFrames=frames,sourcePCMSHA256=digest(pcm),leadingFrames=lead,trailingFrames=tail,sampleRate=rate)

def holdouts(root):
 results={}
 for name,(sha,_) in HOLDOUTS.items():
  p=pathlib.Path(root)/'tests/fixtures'/f'{name}.wav'
  if p.is_symlink():raise ValueError('Linked holdout')
  raw=p.read_bytes()
  if digest(raw)!=sha:raise ValueError('Holdout checksum mismatch')
  results[name]=raw
 return results

def write_matrix(sources,out,expected=None):
 out=pathlib.Path(out);out.mkdir(parents=True,exist_ok=False);records=[]
 for name,raw in sources.items():
  if re.fullmatch('[a-z0-9-]+',name) is None:raise ValueError('Invalid case name')
  for variant,leading,trailing in VARIANTS:
   data,info=pad(raw,leading,trailing);identity=name+'-'+variant;filename=identity+'.wav'
   (out/filename).write_bytes(data)
   records.append(dict(id=identity,file=filename,sha256=digest(data),bytes=len(data),expected=(expected or {}).get(name,''),**info))
 return records

def main():
 if len(sys.argv)!=3:raise SystemExit('Usage: prepare.py retained.zip OUTPUT_DIRECTORY')
 members=read_archive(sys.argv[1],ARCHIVE_SHA,PINNED)
 original=members[TRANSCRIPT].decode('utf-8')
 if original!='Then we insist upon it the study of social deformities and infirmities, and the task of pointing them out with':raise ValueError('Retained transcript changed')
 sources={'retained-reader':members[REFERENCE],**holdouts(ROOT)}
 expected={'retained-reader':'And '+original,**{k:v[1] for k,v in HOLDOUTS.items()}}
 out=pathlib.Path(sys.argv[2]);records=write_matrix(sources,out,expected)
 (out/'retained-transcript.txt').write_bytes(members[TRANSCRIPT])
 (out/'manifest.json').write_text(json.dumps(dict(schemaVersion=1,sourceArtifact=14177206631,archiveSHA256=ARCHIVE_SHA,cases=records,expectedTextBasis={'retained-reader':'Manually specified evaluation hypothesis: And prefixed to retained ASR transcript from prior paired conditioning diagnostic; not independently established ground truth.','conversion-source':'Pinned neutral synthetic fixture requested text.','conversion-reference':'Pinned neutral synthetic fixture requested text.'},scope='ASR context diagnostic only. Expected words are evaluation labels, never inference prompts. No source trimming or production change; no device or likeness verification.'),indent=2)+'\n')
 print('Prepared 12 exact-source diagnostic cases; no inference performed')
if __name__=='__main__':main()
