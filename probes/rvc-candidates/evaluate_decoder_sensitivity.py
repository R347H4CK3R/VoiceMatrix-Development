"""Offline automated diagnostics, not human intelligibility or identity verification."""
import pathlib,sys,os,json,hashlib,wave,math,re,gc
r=pathlib.Path(__file__).parent
sys.path[:0]=[str(r/'deps-vctk-decode'),str(r/'deps-long')]
os.environ.update(HF_HUB_OFFLINE='1',TRANSFORMERS_OFFLINE='1',OMP_NUM_THREADS='2',CUDA_VISIBLE_DEVICES='')
import socket
def offline(*a,**kw):raise RuntimeError('Network disabled during evaluation')
socket.socket.connect=offline;socket.create_connection=offline
import numpy as np,torch
from scipy.signal import resample_poly
from transformers import WhisperProcessor,WhisperForConditionalGeneration,AutoFeatureExtractor,WavLMForXVector
torch.set_num_threads(2);torch.set_num_interop_threads(1)
root=r/'objective-evaluation-01'
manifest=json.loads((root/'model-provenance.json').read_text())
for folder,m in manifest.items():
 for name,digest in m['files'].items():
  assert hashlib.sha256((root/folder/name).read_bytes()).hexdigest()==digest
def load(path):
 with wave.open(str(path)) as w:
  assert w.getsampwidth()==2 and w.getnchannels()==1
  rate=w.getframerate();a=np.frombuffer(w.readframes(w.getnframes()),dtype='<i2').astype(np.float32)/32768
 g=math.gcd(rate,16000);a=resample_poly(a,16000//g,rate//g).astype(np.float32)
 assert 16000<=len(a)<=480000 and np.isfinite(a).all()
 return a
def edits(a,b):
 a=re.findall(r"[a-z0-9']+",a.lower());b=re.findall(r"[a-z0-9']+",b.lower())
 row=list(range(len(b)+1))
 for i,x in enumerate(a,1):
  nxt=[i]
  for j,y in enumerate(b,1):nxt.append(min(nxt[-1]+1,row[j]+1,row[j-1]+(x!=y)))
  row=nxt
 return dict(referenceTokens=len(a),hypothesisTokens=len(b),wordEdits=row[-1],normalizedDisagreement=row[-1]/len(a) if a else None)

candidate=r/'candidate-vctk-p226'
prior=json.loads((candidate/'objective-librispeech-heldout-next.json').read_text())
out=candidate/'objective-librispeech-decoder-sensitivity.json'
assert not out.exists()
def alignment(reference,hypothesis):
 a=re.findall(r"[a-z0-9']+",reference.lower());b=re.findall(r"[a-z0-9']+",hypothesis.lower())
 d=[list(range(len(b)+1))]+[[i]+[0]*len(b) for i in range(1,len(a)+1)]
 for i in range(1,len(a)+1):
  for j in range(1,len(b)+1):d[i][j]=min(d[i-1][j]+1,d[i][j-1]+1,d[i-1][j-1]+(a[i-1]!=b[j-1]))
 i,j=len(a),len(b);ops=[]
 while i or j:
  if i and j and d[i][j]==d[i-1][j-1]+(a[i-1]!=b[j-1]):
   if a[i-1]!=b[j-1]:ops.append(dict(operation='substitute',referenceIndex=i-1,reference=a[i-1],hypothesis=b[j-1]))
   i-=1;j-=1
  elif i and d[i][j]==d[i-1][j]+1:
   ops.append(dict(operation='delete',referenceIndex=i-1,reference=a[i-1],hypothesis=None));i-=1
  else:
   ops.append(dict(operation='insert',referenceIndex=i,reference=None,hypothesis=b[j-1]));j-=1
 assert len(ops)==edits(reference,hypothesis)['wordEdits']
 return list(reversed(ops))
assert len(alignment('a choice is','their choices are'))==3
processor=WhisperProcessor.from_pretrained(root/'whisper',local_files_only=True)
model=WhisperForConditionalGeneration.from_pretrained(root/'whisper',local_files_only=True,attn_implementation='eager').eval()
results={}
for name in ('2961-960-0003','4507-16021-0031'):
 results[name]={};reference=prior['referenceTexts'][name]
 for kind in ('input','0','0125'):
  path=candidate/('librispeech-'+name+'-'+('0' if kind=='input' else kind))/('prepared-input.wav' if kind=='input' else 'converted-native.wav')
  digest=hashlib.sha256(path.read_bytes()).hexdigest();assert digest==prior['records'][name][kind]['sha256']
  a=load(path)
  v=processor(a,sampling_rate=16000,return_tensors='pt',return_attention_mask=True)
  with torch.inference_mode():tokens=model.generate(input_features=v.input_features,attention_mask=v.attention_mask,do_sample=False,num_beams=3,max_new_tokens=128,forced_decoder_ids=None)
  text=processor.batch_decode(tokens,skip_special_tokens=True)[0].strip()
  old=prior['records'][name][kind]['transcript']
  record=dict(audioSHA256=digest,greedyTranscript=old,beam3Transcript=text,greedyWER=edits(reference,old),beam3WER=edits(reference,text),greedyAlignment=alignment(reference,old),beam3Alignment=alignment(reference,text),decoderSequenceTokens=int(tokens.shape[-1]),generationMaxNewTokens=128)
  assert int(tokens.shape[-1])<128
  results[name][kind]=record
  print(json.dumps(dict(case=name,kind=kind,greedyEdits=record['greedyWER']['wordEdits'],beam3Edits=record['beam3WER']['wordEdits'],beam3Transcript=text)),flush=True)
report=dict(results=results,evaluatorModels=manifest,referenceTexts=prior['referenceTexts'],scope='Recognizer decoding sensitivity on preserved regression WAVs; no audio/model/default changes',preselectedBeams=3,greedyBaselineSHA256=hashlib.sha256((candidate/'objective-librispeech-heldout-next.json').read_bytes()).hexdigest(),humanListeningVerified=False,physicalIPhoneVerified=False,productionQualified=False)
out.write_text(json.dumps(report,indent=2))
print('Decoder sensitivity evaluation completed',flush=True)
