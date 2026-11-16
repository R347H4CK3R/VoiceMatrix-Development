"""Require reference-only context receipts after the original strict route checker."""
import hashlib,importlib.util,json,math,pathlib,re,sys
REVISION='7dd20fe6b1797d35f5e3307e8b1732d9a178edfe'
def safe(name):
 if not isinstance(name,str) or re.fullmatch('[A-Za-z0-9_.-]+',name) is None or name in ('.','..'):raise ValueError('Unsafe receipt path')
 return name

def read(path):
 path=pathlib.Path(path)
 if path.is_symlink() or not path.is_file() or path.stat().st_size>1_048_576:raise ValueError('Missing, linked or excessive receipt')
 return json.loads(path.read_text())

def digest(path):
 path=pathlib.Path(path)
 if path.is_symlink() or not path.is_file() or path.stat().st_size>8_388_608:raise ValueError('Invalid audio')
 return hashlib.sha256(path.read_bytes()).hexdigest()

def receipt(path,sha,context):
 r=read(path)
 if r.get('schemaVersion')!=2 or r.get('modelRevision')!=REVISION or r.get('inputSHA256')!=sha or re.fullmatch('[a-f0-9]{64}',r.get('transcriptSHA256','')) is None:raise ValueError('Incomplete or mismatched receipt')
 count=r.get('tokenCount');confidence=r.get('meanTokenConfidence')
 if type(count)!=int or not 1<=count<=4096 or type(confidence) not in (int,float) or not math.isfinite(confidence) or not .35<=confidence<=1:raise ValueError('Invalid token evidence')
 leading=r.get('referenceLeadingSeconds')
 if context is None:
  if leading is not None:raise ValueError('Output verifier unexpectedly padded')
 elif type(leading) not in (int,float) or leading!=context or r.get('recoveryTailSeconds') is not None:raise ValueError('Reference context missing, changed or doubled')
 return r

def verify_receipts(root,report):
 root=pathlib.Path(root);ids=report.get('importedIDs',[]);rows=report.get('newSpeeches',[])
 if len(ids)!=2 or len(set(ids))!=2 or len(rows)!=2 or {r.get('voiceID') for r in rows}!=set(ids):raise ValueError('Require two completed distinct voices')
 jobs=root/'work/Jobs'
 if jobs.is_symlink():raise ValueError('Linked jobs')
 folders=list(jobs.iterdir())
 if len(folders)!=1 or not folders[0].is_dir() or folders[0].is_symlink():raise ValueError('Expected exactly one retained job')
 folder=folders[0];saved={}
 for p in folder.glob('candidate-*.json'):
  c=read(p)
  for event in c.get('events',[]):
   if event.get('outcome')=='saved':
    identity=event.get('voiceID')
    if identity in saved:raise ValueError('Duplicate saved candidate')
    saved[identity]=(c,event)
 if set(saved)!=set(ids):raise ValueError('Incomplete saved candidates')
 for r in rows:
  c,event=saved[r['voiceID']];identity=safe(c['id']);reference=digest(folder/f'reference-{identity}.wav');preview=digest(folder/f'preview-{identity}.wav')
  if reference!=event.get('referenceSHA256') or reference!=r.get('referenceSHA256') or preview!=event.get('previewSHA256'):raise ValueError('Changed candidate audio')
  receipt(folder/f'transcription-evidence-{identity}.json',reference,.25)
  receipt(folder/f'preview-asr-evidence-{identity}.json',preview,None)
  final=digest(root/'work'/safe(r['file']))
  if final!=r.get('newSpeechSHA256'):raise ValueError('Changed final audio')
  receipt(root/'work'/safe(r['asrFile']),final,None)
 return dict(referenceReceipts=2,previewReceipts=2,finalReceipts=2,referenceLeadingSeconds=.25,outputsUseUnchangedContext=True)

def main():
 root=pathlib.Path(sys.argv[1]);path=pathlib.Path(__file__).parent/'two-complete-readers/check.py'
 spec=importlib.util.spec_from_file_location('strict_route',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
 report=read(root/'pipeline-evidence.json');fixture=read(root/'fixture.json')
 m.verify_sources(root,fixture,read(root/'source-transcript-check.json'));m.verify(root,fixture,report)
 proof=verify_receipts(root,report);(root/'reference-context-receipts.json').write_text(json.dumps(proof,indent=2)+'\n');print(json.dumps(proof))
if __name__=='__main__':main()
